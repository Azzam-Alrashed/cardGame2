import Observation
import SwiftUI

/// Drives one table: owns the engine, plays the AI seats, and holds the
/// presentation state the views animate from.
///
/// The round reads top to bottom as `await`s, and the human's turn is simply
/// where the driver stops and returns. The view model never reaches for a
/// hidden hand: every hand it reads goes through the engine's
/// `hand(of:asSeenBy:)`, with the human as the viewer, so a hand it cannot
/// draw is a hand it does not have.
@MainActor
@Observable
final class GameTableViewModel {

    /// What, if anything, the table is waiting on the human for.
    enum Interaction: Equatable {
        /// The AI is acting, cards are flying, or the round is being scored.
        case watching
        case readyToDeal
        /// Fold, match, raise or go all-in.
        case choosingAction
        /// Offer a rival money to leave the round.
        case offeringSharah
        /// Someone has offered the human money to leave.
        case respondingToSharah(SharahOffer)
        case roundOver
        case gameOver
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
    private(set) var result: RoundResult?
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
    /// Whether the human has had their turn at offering Sharah this round.
    private var humanHasNegotiated = false

    init(
        players: [Player] = Table.demo,
        humanSeat: Seat = .south,
        seed: UInt64? = nil,
        timing: Timing = .standard
    ) {
        self.engine = GameEngine(players: players, seed: seed)
        self.humanSeat = humanSeat
        self.timing = timing
        self.ai = Dictionary(uniqueKeysWithValues: players.enumerated().map { index, player in
            let personality: AIStrategy.Personality
            switch index % 3 {
            case 0: personality = .balanced
            case 1: personality = .cautious
            default: personality = .reckless
            }
            return (player.seat, AIStrategy(personality: personality, seed: seed.map { $0 &+ UInt64(index) }))
        })
    }

    // MARK: - Reading the table

    var seats: [Seat] { engine.roster.map(\.seat) }

    var humanID: PlayerID? { engine.player(at: humanSeat)?.id }

    var human: Player? { engine.player(at: humanSeat) }

    func player(at seat: Seat) -> Player? { engine.player(at: seat) }

    /// A hand the human is entitled to see: their own, or a revealed one.
    func hand(at seat: Seat) -> Hand? {
        guard let humanID, let id = engine.player(at: seat)?.id else { return nil }
        return engine.hand(of: id, asSeenBy: humanID)
    }

    func isTurn(of seat: Seat) -> Bool {
        guard case .betting(let turn) = engine.phase else { return false }
        return engine.player(at: seat)?.id == turn
    }

    func isTopBettor(_ seat: Seat) -> Bool {
        engine.player(at: seat)?.id == engine.topBettor
    }

    /// Cards are face up for the human all round, and for everyone still in at
    /// the reveal.
    func showsFaces(at seat: Seat) -> Bool {
        seat == humanSeat || faceUpSeats.contains(seat)
    }

    var canDeal: Bool { engine.canStartRound }

    /// Every ordinary bet the human may make this turn.
    var humanBetRange: BetRange {
        humanID.map { engine.betRange(for: $0) } ?? .empty
    }

    /// Bets to offer in the picker, capped so a large stack cannot fill the
    /// screen. The all-in button covers the top of the range.
    var humanBetOptions: [Int] {
        humanBetRange.options(limit: 40)
    }

    /// What the human would commit by going all-in, or nil when they have
    /// nothing left.
    var humanAllIn: Int? {
        guard let humanID, let balance = engine.players[humanID]?.balance, balance > 0 else { return nil }
        return balance
    }

    func cost(of action: BetAction) -> Int? {
        guard let humanID, let balance = engine.players[humanID]?.balance else { return nil }
        return BettingRules.cost(of: action, balance: balance)
    }

    /// Sharah amounts the human could offer, as a few round fractions of what
    /// they have free.
    var humanSharahAmounts: [Int] {
        guard let humanID else { return [] }
        let available = engine.availableBalance(of: humanID)
        guard available > 0 else { return [] }
        let candidates = [available / 8, available / 4, available / 2, available]
        return Array(Set(candidates.filter { $0 > 0 })).sorted()
    }

    /// Who the human's offer would go to. The engine allows any player in the
    /// round; the table UI aims at the loudest bet, which is a choice of
    /// interface, not a rule.
    var sharahTarget: PublicPlayerView? {
        guard let humanID else { return nil }
        return engine.publicView(for: humanID).opponentsInRound.max { $0.bet < $1.bet }
    }

    var winnerNames: [String] {
        (result?.winners ?? []).compactMap { engine.players[$0]?.name }
    }

    var gameWinnerName: String? {
        guard case .gameOver(let winner) = engine.phase else { return nil }
        return engine.players[winner]?.name
    }

    // MARK: - The round

    /// Shuffles, deals, and hands over to the betting loop.
    func startRound() async {
        do {
            result = nil
            message = nil
            humanHasNegotiated = false
            interaction = .watching

            withAnimation(.easeIn(duration: 0.25)) {
                bubbles = [:]
                faceUpSeats = []
                dealtCards = [:]
                foldedSeats = []
            }

            try engine.startRound()

            // One card at a time, round the table, four times over — the order
            // the engine itself dealt them in.
            for pass in 0..<GameRules.handSize {
                for id in engine.turnOrder {
                    guard let seat = engine.seat(of: id) else { continue }
                    try? await Task.sleep(for: timing.dealStagger)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        dealtCards[seat] = pass + 1
                    }
                }
            }

            try engine.finishDealing()
            try engine.beginBetting()
            await advance()
        } catch {
            report(error)
        }
    }

    /// Plays every AI turn it can, then stops wherever the human is needed.
    private func advance() async {
        switch engine.phase {
        case .waitingForPlayers, .roundOver:
            interaction = .readyToDeal

        case .dealing, .privateHands:
            interaction = .watching

        case .betting(let turn) where turn == humanID:
            interaction = .choosingAction

        case .betting(let turn):
            interaction = .watching
            try? await Task.sleep(for: timing.aiThinking)
            await playAITurn(for: turn)

        case .negotiation:
            await runNegotiation()

        case .showdown, .settlement:
            await finishRound()

        case .gameOver:
            interaction = .gameOver
        }
    }

    private func playAITurn(for id: PlayerID) async {
        guard let seat = engine.seat(of: id),
              let hand = engine.hand(of: id, asSeenBy: id),
              let balance = engine.players[id]?.balance
        else { return }

        // The AI is handed its own hand and the public table — never the
        // engine's participation table.
        let action = ai[seat]?.decideBet(
            hand: hand,
            balance: balance,
            table: engine.publicView(for: id)
        ) ?? .fold

        do {
            let amount = try engine.act(action, by: id)
            if action == .fold {
                showFold(at: seat)
            } else {
                show(bet: amount, at: seat)
            }
            await advance()
        } catch {
            report(error)
        }
    }

    /// Lets the human offer, collects the AI's offers, then rules on each one.
    private func runNegotiation() async {
        interaction = .watching

        if let humanID,
           !humanHasNegotiated,
           engine.standing(of: humanID) == .committed,
           sharahTarget != nil,
           !humanSharahAmounts.isEmpty {
            interaction = .offeringSharah
            return
        }

        await collectAIOffers()
        await resolveOffers()
    }

    private func collectAIOffers() async {
        for id in engine.playersInRound where id != humanID {
            guard let seat = engine.seat(of: id),
                  let hand = engine.hand(of: id, asSeenBy: id)
            else { continue }
            let table = engine.publicView(for: id)
            guard let offer = ai[seat]?.decideSharahOffer(
                hand: hand,
                available: engine.availableBalance(of: id),
                table: table
            ) else { continue }
            try? await Task.sleep(for: timing.offerArrival)
            try? engine.offerSharah(offer.amount, from: id, to: offer.to)
        }
    }

    /// Each pending offer is ruled on by whoever received it. The human stops
    /// the driver; the AI answers for itself.
    private func resolveOffers() async {
        while let offer = engine.offers.first(where: \.isPending) {
            if offer.to == humanID {
                interaction = .respondingToSharah(offer)
                return
            }
            guard let seat = engine.seat(of: offer.to),
                  let hand = engine.hand(of: offer.to, asSeenBy: offer.to)
            else {
                try? engine.respondToSharah(offer.id, accept: false, by: offer.to)
                continue
            }
            try? await Task.sleep(for: timing.offerArrival)
            let accepts = ai[seat]?.respondToSharah(
                offer,
                hand: hand,
                bet: engine.bet(of: offer.to),
                table: engine.publicView(for: offer.to)
            ) ?? false
            try? engine.respondToSharah(offer.id, accept: accepts, by: offer.to)
            if accepts { showFold(at: seat) }
        }

        await finishRound()
    }

    /// Turns the cards up, moves the money, checks for a game winner.
    func finishRound() async {
        interaction = .watching
        try? await Task.sleep(for: timing.beforeReveal)
        do {
            if case .negotiation = engine.phase { try engine.closeNegotiation() }
            if case .showdown = engine.phase { try engine.settle() }
            let finished = try engine.checkGameEnd()
            present(finished)
        } catch {
            report(error)
        }
    }

    private func present(_ finished: RoundResult) {
        result = finished
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            faceUpSeats = Set(finished.revealedHands.keys.compactMap { engine.seat(of: $0) })
        }
        if case .gameOver = engine.phase {
            interaction = .gameOver
        } else {
            interaction = .roundOver
        }
    }

    // MARK: - Human actions

    func take(_ action: BetAction) async {
        guard let humanID else { return }
        do {
            let amount = try engine.act(action, by: humanID)
            if action == .fold {
                showFold(at: humanSeat)
            } else {
                show(bet: amount, at: humanSeat)
            }
            await advance()
        } catch {
            report(error)
        }
    }

    func offerSharah(_ amount: Int) async {
        guard let humanID, let target = sharahTarget else { return }
        humanHasNegotiated = true
        do {
            try engine.offerSharah(amount, from: humanID, to: target.id)
            message = "Offered \(amount) to \(target.name)"
        } catch {
            message = "\(error)"
        }
        await runNegotiation()
    }

    func declineToOfferSharah() async {
        humanHasNegotiated = true
        await runNegotiation()
    }

    func respond(to offer: SharahOffer, accept: Bool) async {
        guard let humanID else { return }
        do {
            try engine.respondToSharah(offer.id, accept: accept, by: humanID)
            if accept {
                message = "Took \(offer.amount) and left the round"
                showFold(at: humanSeat)
            }
            await resolveOffers()
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

    private func showFold(at seat: Seat) {
        withAnimation(.easeInOut(duration: 0.3)) {
            foldedSeats.insert(seat)
            bubbles[seat] = nil
        }
    }

    private func report(_ error: Error) {
        message = "\(error)"
        interaction = .roundOver
    }
}
