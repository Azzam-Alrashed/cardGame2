import Foundation

/// What the engine is waiting for.
public enum GamePhase: Hashable, Sendable {
    /// Between rounds. Call `startRound` to deal.
    case idle
    /// Waiting for `seat` to bet or withdraw.
    case betting(seat: Seat)
    /// All bets are in. Entrants may send offers; the top bettor resolves them.
    case negotiation
    /// Cards are up and coins have moved.
    case reveal(RoundOutcome)
}

/// The result of a scored round.
public struct RoundOutcome: Hashable, Sendable {
    public let winner: PlayerID?
    public let pot: Int
    /// Final hand of every player who was still in the round.
    public let revealedHands: [PlayerID: Hand]
    /// Net change in coins per player, including offer payments.
    public let coinChanges: [PlayerID: Int]
    /// Offers the top bettor accepted, which were paid out only if they won.
    public let settledOffers: [Offer]
}

public enum GameError: Error, Equatable, Sendable {
    case wrongPhase
    case notYourTurn
    case illegalBet(Int)
    case illegalOffer(Int)
    case notAnEntrant
    case notTopBettor
    case unknownPlayer
    case unknownOffer
    case offerAlreadyResolved
}

/// The whole game, as a value you can hold, copy and assert against. No views,
/// no timers, no animation — a caller drives it one action at a time and reads
/// `phase` to know what it wants next.
public struct GameEngine: Sendable {
    public private(set) var players: [PlayerID: Player]
    public private(set) var seating: [Seat: PlayerID]
    public private(set) var phase: GamePhase = .idle
    public private(set) var participation: [PlayerID: RoundParticipation] = [:]
    public private(set) var offers: [Offer] = []

    /// Rounds completed so far; also drives the dealer rotation.
    public private(set) var roundIndex = 0
    public private(set) var turnOrder: [Seat] = []
    public private(set) var highestBet = 0
    public private(set) var topBettor: PlayerID?

    /// How the round's coins move at settlement.
    public let payout: GameRules.Payout

    private var rng: RandomGenerator

    public init(
        players: [Player],
        payout: GameRules.Payout = GameRules.defaultPayout,
        seed: UInt64? = nil
    ) {
        precondition(players.count == GameRules.seatCount, "the game seats exactly \(GameRules.seatCount) players")
        self.players = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        self.seating = Dictionary(uniqueKeysWithValues: players.map { ($0.seat, $0.id) })
        self.payout = payout
        self.rng = RandomGenerator(seed: seed)
    }

    // MARK: - Reading the table

    public func player(at seat: Seat) -> Player? {
        seating[seat].flatMap { players[$0] }
    }

    public func seat(of id: PlayerID) -> Seat? {
        players[id]?.seat
    }

    /// Players still in the round, in turn order.
    public var entrants: [PlayerID] {
        turnOrder.compactMap { seating[$0] }.filter { participation[$0]?.isEntrant == true }
    }

    /// Players ranked by coins, richest first; ties broken by name for stability.
    public var leaderboard: [Player] {
        players.values.sorted {
            $0.coins != $1.coins ? $0.coins > $1.coins : $0.name < $1.name
        }
    }

    /// Bets the player whose turn it is may legally place.
    public func betRange(for id: PlayerID) -> StakeRange {
        guard let coins = players[id]?.coins else { return .empty }
        return GameRules.betRange(coins: coins, highestBet: highestBet)
    }

    /// Offers `id` may legally send. Empty unless they are an entrant who is
    /// not the top bettor and has no offer in flight.
    public func offerRange(for id: PlayerID) -> StakeRange {
        guard case .negotiation = phase,
              let coins = players[id]?.coins,
              participation[id]?.isEntrant == true,
              id != topBettor,
              !offers.contains(where: { $0.sender == id })
        else { return .empty }
        return GameRules.offerRange(coins: coins, topBet: highestBet)
    }

    // MARK: - Driving the round

    /// Shuffles, deals four cards to each seat and opens betting.
    public mutating func startRound() throws {
        switch phase {
        case .idle, .reveal: break
        default: throw GameError.wrongPhase
        }

        var deck = Deck()
        deck.shuffle(using: &rng)

        turnOrder = GameRules.turnOrder(round: roundIndex)
        participation = [:]
        offers = []
        highestBet = 0
        topBettor = nil

        for seat in turnOrder {
            guard let id = seating[seat] else { continue }
            participation[id] = RoundParticipation(hand: Hand(cards: deck.deal(GameRules.handSize)))
        }

        phase = .betting(seat: turnOrder[0])
    }

    /// Enters the round for `amount` coins, which must fall in
    /// `betRange(for:)`.
    public mutating func bet(_ amount: Int, from id: PlayerID) throws {
        try requireTurn(of: id)
        guard betRange(for: id).contains(amount) else { throw GameError.illegalBet(amount) }

        participation[id]?.bet = amount
        participation[id]?.hasWithdrawn = false
        if amount > highestBet {
            highestBet = amount
            topBettor = id
        }
        advanceTurn()
    }

    /// Sits the round out. Always legal on your turn.
    public mutating func withdraw(_ id: PlayerID) throws {
        try requireTurn(of: id)
        participation[id]?.bet = 0
        participation[id]?.hasWithdrawn = true
        advanceTurn()
    }

    /// Puts an offer to the top bettor. Final once sent.
    public mutating func submitOffer(_ coins: Int, from id: PlayerID) throws {
        guard case .negotiation = phase else { throw GameError.wrongPhase }
        guard players[id] != nil else { throw GameError.unknownPlayer }
        guard participation[id]?.isEntrant == true else { throw GameError.notAnEntrant }
        guard offerRange(for: id).contains(coins) else { throw GameError.illegalOffer(coins) }

        offers.append(Offer(sender: id, coins: coins))
    }

    /// The top bettor's call on a pending offer. Final once made.
    ///
    /// Accepting pulls the sender out of the round; they pay the offer only if
    /// the top bettor goes on to win.
    public mutating func resolve(
        offer offerID: UUID,
        as resolution: Offer.Resolution,
        by id: PlayerID
    ) throws {
        guard case .negotiation = phase else { throw GameError.wrongPhase }
        guard id == topBettor else { throw GameError.notTopBettor }
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { throw GameError.unknownOffer }
        guard offers[index].isPending else { throw GameError.offerAlreadyResolved }

        offers[index].resolution = resolution
        if resolution == .accepted {
            participation[offers[index].sender]?.hasWithdrawn = true
        }
    }

    /// Closes negotiation, scores the remaining hands and moves the coins.
    ///
    /// The top bettor decides when this happens; a UI is expected to call it on
    /// a timeout too.
    @discardableResult
    public mutating func endRound() throws -> RoundOutcome {
        guard case .negotiation = phase else { throw GameError.wrongPhase }

        let outcome = settle()
        apply(outcome)
        roundIndex += 1
        phase = .reveal(outcome)
        return outcome
    }

    // MARK: - Settlement

    /// Scores the round without mutating anything.
    ///
    /// Hands are compared on score alone; a tie goes to whoever sits earliest
    /// in this round's turn order. Losing entrants always pay the bet they
    /// placed; what the winner collects depends on `payout`.
    private func settle() -> RoundOutcome {
        let contenders = entrants
        guard !contenders.isEmpty else {
            return RoundOutcome(winner: nil, pot: 0, revealedHands: [:], coinChanges: [:], settledOffers: [])
        }

        var hands: [PlayerID: Hand] = [:]
        for id in contenders {
            if let hand = participation[id]?.hand { hands[id] = hand }
        }

        // `contenders` is already in turn order, so max(by: <) keeps the
        // earliest seat on a tie.
        let winner = contenders.max { lhs, rhs in
            (hands[lhs]?.score ?? 0) < (hands[rhs]?.score ?? 0)
        }

        var changes: [PlayerID: Int] = [:]
        var forfeited = 0
        for id in contenders where id != winner {
            let bet = participation[id]?.bet ?? 0
            changes[id, default: 0] -= bet
            forfeited += bet
        }
        if let winner {
            switch payout {
            case .conserving:
                changes[winner, default: 0] += forfeited
            case .topBetToWinner:
                changes[winner, default: 0] += highestBet
            }
        }

        let accepted = offers.filter { $0.resolution == .accepted }
        var settled: [Offer] = []
        if let winner, winner == topBettor {
            for offer in accepted {
                changes[offer.sender, default: 0] -= offer.coins
                changes[winner, default: 0] += offer.coins
                settled.append(offer)
            }
        }

        return RoundOutcome(
            winner: winner,
            pot: highestBet,
            revealedHands: hands,
            coinChanges: changes,
            settledOffers: settled
        )
    }

    private mutating func apply(_ outcome: RoundOutcome) {
        for (id, change) in outcome.coinChanges {
            players[id]?.coins += change
        }
    }

    // MARK: - Turn plumbing

    private func requireTurn(of id: PlayerID) throws {
        guard case .betting(let seat) = phase else { throw GameError.wrongPhase }
        guard players[id] != nil else { throw GameError.unknownPlayer }
        guard seating[seat] == id else { throw GameError.notYourTurn }
    }

    private mutating func advanceTurn() {
        guard case .betting(let seat) = phase,
              let index = turnOrder.firstIndex(of: seat)
        else { return }

        let next = index + 1
        if next < turnOrder.count {
            phase = .betting(seat: turnOrder[next])
            return
        }

        // Betting is over. With nobody in, there is nothing to negotiate over.
        if entrants.isEmpty {
            let outcome = RoundOutcome(winner: nil, pot: 0, revealedHands: [:], coinChanges: [:], settledOffers: [])
            roundIndex += 1
            phase = .reveal(outcome)
        } else {
            phase = .negotiation
        }
    }
}
