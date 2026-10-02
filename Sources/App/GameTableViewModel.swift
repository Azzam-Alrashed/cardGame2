import Observation
import SwiftUI

/// Drives one table: owns the engine, plays the AI seats, and holds the
/// presentation state the views animate from.
///
/// The old controller chained `DispatchQueue.main.asyncAfter` calls through
/// animation completion handlers, which made the round order hard to follow.
/// Here the round reads top to bottom as `await`s, and the human's turn is
/// simply where the driver stops and returns.
@MainActor
@Observable
final class GameTableViewModel {

    /// What, if anything, the table is waiting on the human for.
    enum Interaction: Equatable {
        /// The AI is acting, cards are flying, or the round is being scored.
        case watching
        case readyToDeal
        /// Enter the round or withdraw.
        case choosingAction
        case pickingBet
        /// An entrant who is not the top bettor may buy their way out.
        case offeringToWithdraw
        /// The top bettor rules on the offers and calls the reveal.
        case resolvingOffers
        case roundOver
    }

    enum Panel: String, Identifiable, CaseIterable {
        case offers, leaderboard, info
        var id: String { rawValue }
    }

    /// How long each beat of a round takes. Tests pass `.immediate` so a
    /// round resolves as fast as the engine can score it.
    struct Timing: Sendable {
        var dealStagger: Duration
        var aiThinking: Duration
        var offerArrival: Duration
        var beforeReveal: Duration

        static let standard = Timing(
            dealStagger: .milliseconds(70),
            aiThinking: .milliseconds(900),
            offerArrival: .milliseconds(700),
            beforeReveal: .milliseconds(500)
        )

        static let immediate = Timing(
            dealStagger: .zero,
            aiThinking: .zero,
            offerArrival: .zero,
            beforeReveal: .zero
        )
    }

    let timing: Timing

    private(set) var engine: GameEngine
    let humanSeat: Seat

    private(set) var interaction: Interaction = .readyToDeal
    private(set) var outcome: RoundOutcome?
    private(set) var message: String?

    /// Cards dealt to each seat so far, so the deal can stagger.
    private(set) var dealtCards: [Seat: Int] = [:]
    /// Seats whose cards have slid off the edge.
    private(set) var foldedSeats: Set<Seat> = []
    /// Bet shown in each seat's bubble.
    private(set) var bubbles: [Seat: Int] = [:]
    /// Seats showing their faces at the reveal.
    private(set) var faceUpSeats: Set<Seat> = []

    var openPanel: Panel?

    private var ai: [Seat: AIStrategy]

    init(
        players: [Player] = Table.demo,
        humanSeat: Seat = .south,
        seed: UInt64? = nil,
        timing: Timing = .standard
    ) {
        self.engine = GameEngine(players: players, seed: seed)
        self.humanSeat = humanSeat
        self.timing = timing
        self.ai = Dictionary(uniqueKeysWithValues: Seat.allCases.enumerated().map { index, seat in
            let personality: AIStrategy.Personality
            switch index % 3 {
            case 0: personality = .balanced
            case 1: personality = .cautious
            default: personality = .reckless
            }
            return (seat, AIStrategy(personality: personality, seed: seed.map { $0 &+ UInt64(index) }))
        })
    }

    // MARK: - Reading the table

    var humanID: PlayerID? { engine.player(at: humanSeat)?.id }

    var human: Player? { engine.player(at: humanSeat) }

    func player(at seat: Seat) -> Player? { engine.player(at: seat) }

    func hand(at seat: Seat) -> Hand? {
        engine.player(at: seat).flatMap { engine.participation[$0.id]?.hand }
    }

    func isTurn(of seat: Seat) -> Bool {
        if case .betting(let active) = engine.phase { return active == seat }
        return false
    }

    func isTopBettor(_ seat: Seat) -> Bool {
        engine.player(at: seat)?.id == engine.topBettor
    }

    /// Cards are shown face up for the human all round, and for everyone still
    /// in at the reveal.
    func showsFaces(at seat: Seat) -> Bool {
        seat == humanSeat || faceUpSeats.contains(seat)
    }

    var humanBetRange: StakeRange {
        humanID.map { engine.betRange(for: $0) } ?? .empty
    }

    var humanOfferRange: StakeRange {
        humanID.map { engine.offerRange(for: $0) } ?? .empty
    }

    /// Offers the human must rule on, as the top bettor.
    var offersAwaitingHuman: [Offer] {
        guard let humanID, engine.topBettor == humanID else { return [] }
        return engine.offers
    }

    var winnerName: String? {
        outcome?.winner.flatMap { engine.players[$0]?.name }
    }

    // MARK: - The round

    /// Shuffles, deals, and hands over to the betting loop.
    func startRound() async {
        do {
            outcome = nil
            message = nil
            interaction = .watching

            withAnimation(.easeIn(duration: 0.25)) {
                bubbles = [:]
                faceUpSeats = []
                dealtCards = [:]
                foldedSeats = []
            }

            try engine.startRound()

            // One card at a time, round the table, twice over — as the old
            // throwCardAnimation did, minus the recursion.
            for round in 0..<GameRules.handSize {
                for seat in engine.turnOrder {
                    try? await Task.sleep(for: timing.dealStagger)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        dealtCards[seat] = round + 1
                    }
                }
            }

            await advance()
        } catch {
            report(error)
        }
    }

    /// Plays every AI turn it can, then stops wherever the human is needed.
    private func advance() async {
        switch engine.phase {
        case .idle:
            interaction = .readyToDeal

        case .betting(let seat) where seat == humanSeat:
            interaction = humanBetRange.isEmpty ? .watching : .choosingAction
            // A human with nothing they can afford simply sits the round out.
            if humanBetRange.isEmpty, let humanID {
                try? await Task.sleep(for: timing.aiThinking)
                await fold(humanID, at: humanSeat)
            }

        case .betting(let seat):
            interaction = .watching
            try? await Task.sleep(for: timing.aiThinking)
            await playAITurn(at: seat)

        case .negotiation:
            await runNegotiation()

        case .reveal(let result):
            await present(result)
        }
    }

    private func playAITurn(at seat: Seat) async {
        guard let id = engine.player(at: seat)?.id,
              let hand = engine.participation[id]?.hand
        else { return }

        switch ai[seat]?.decideBet(hand: hand, range: engine.betRange(for: id)) ?? .withdraw {
        case .bet(let amount):
            do {
                try engine.bet(amount, from: id)
                show(bet: amount, at: seat)
                await advance()
            } catch {
                report(error)
            }
        case .withdraw:
            await fold(id, at: seat)
        }
    }

    private func fold(_ id: PlayerID, at seat: Seat) async {
        do {
            try engine.withdraw(id)
            withAnimation(.easeInOut(duration: 0.3)) {
                foldedSeats.insert(seat)
                bubbles[seat] = nil
            }
            await advance()
        } catch {
            report(error)
        }
    }

    /// Collects the AI's offers, then either waits on the human top bettor or
    /// lets the AI top bettor rule and call the reveal.
    private func runNegotiation() async {
        interaction = .watching

        for id in engine.entrants where id != engine.topBettor {
            guard let seat = engine.seat(of: id), seat != humanSeat else { continue }
            guard let hand = engine.participation[id]?.hand else { continue }
            if let amount = ai[seat]?.decideOffer(hand: hand, range: engine.offerRange(for: id)) {
                try? await Task.sleep(for: timing.offerArrival)
                try? engine.submitOffer(amount, from: id)
            }
        }

        guard let humanID else { return }

        // The top bettor rules on any offers and decides when cards come up,
        // so the human stops here whether offers arrived or not.
        if engine.topBettor == humanID {
            interaction = .resolvingOffers
            return
        }

        if !humanOfferRange.isEmpty {
            interaction = .offeringToWithdraw
            return
        }

        await letAIResolveAndReveal()
    }

    private func letAIResolveAndReveal() async {
        guard let top = engine.topBettor,
              let seat = engine.seat(of: top),
              let hand = engine.participation[top]?.hand
        else { return await endRound() }

        for offer in engine.offers where offer.isPending {
            try? await Task.sleep(for: timing.offerArrival)
            let call = ai[seat]?.decideOfferResolution(hand: hand, offer: offer) ?? .rejected
            try? engine.resolve(offer: offer.id, as: call, by: top)
        }

        await endRound()
    }

    /// Closes negotiation and scores the round.
    func endRound() async {
        interaction = .watching
        try? await Task.sleep(for: timing.beforeReveal)
        do {
            let result = try engine.endRound()
            await present(result)
        } catch {
            report(error)
        }
    }

    private func present(_ result: RoundOutcome) async {
        outcome = result
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            faceUpSeats = Set(result.revealedHands.keys.compactMap { engine.seat(of: $0) })
        }
        interaction = .roundOver
    }

    // MARK: - Human actions

    func chooseToEnterRound() {
        interaction = .pickingBet
    }

    func cancelBetPicker() {
        interaction = .choosingAction
    }

    func placeBet(_ amount: Int) async {
        guard let humanID else { return }
        do {
            try engine.bet(amount, from: humanID)
            show(bet: amount, at: humanSeat)
            await advance()
        } catch {
            report(error)
        }
    }

    func withdrawFromRound() async {
        guard let humanID else { return }
        await fold(humanID, at: humanSeat)
    }

    func sendOffer(_ amount: Int) async {
        guard let humanID else { return }
        do {
            try engine.submitOffer(amount, from: humanID)
            message = "Offered \(amount) to withdraw"
            await letAIResolveAndReveal()
        } catch {
            report(error)
        }
    }

    func declineToOffer() async {
        await letAIResolveAndReveal()
    }

    func resolve(_ offer: Offer, as resolution: Offer.Resolution) {
        guard let humanID else { return }
        do {
            try engine.resolve(offer: offer.id, as: resolution, by: humanID)
            if resolution == .accepted, let seat = engine.seat(of: offer.sender) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    foldedSeats.insert(seat)
                    bubbles[seat] = nil
                }
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Presentation plumbing

    private func show(bet amount: Int, at seat: Seat) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
            bubbles[seat] = amount
        }
    }

    private func report(_ error: Error) {
        message = "\(error)"
        interaction = .roundOver
    }
}
