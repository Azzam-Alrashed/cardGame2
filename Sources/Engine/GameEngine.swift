import Foundation

/// Everything that happened in one round.
public struct RoundResult: Hashable, Sendable {
    public let roundIndex: Int
    /// Hands of the players who reached the showdown. Folded and bought-out
    /// players are absent, permanently.
    public let revealedHands: [PlayerID: Hand]
    /// Every bet committed this round, including by players who later left via
    /// Sharah.
    public let bets: [PlayerID: Int]
    public let ledger: SettlementLedger
    /// Sharah offers that were accepted. The money moved when they were
    /// accepted, not here.
    public let acceptedOffers: [SharahOffer]
    /// Players who hit zero and are out of the game.
    public let eliminated: [PlayerID]
    /// Set when someone reached the target and the game is over.
    public let gameWinner: PlayerID?

    public var winners: [PlayerID] { ledger.winners }
    public var highestBet: Int { ledger.highestBet }

    public func reward(for id: PlayerID) -> Int { ledger.rewards[id] ?? 0 }
    public func loss(for id: PlayerID) -> Int { ledger.losses[id] ?? 0 }
    public func netChange(for id: PlayerID) -> Int { ledger.netChange[id] ?? 0 }
}

public enum GameError: Error, Equatable, Sendable {
    case wrongPhase
    case notYourTurn
    case unknownPlayer
    case playerEliminated
    case notEnoughPlayers
    case tooManyPlayers
    case duplicateSeat
    case illegalAction(BetAction)
    case illegalBet(Int)
    case notInRound
    case cannotOfferToSelf
    case illegalSharahAmount(Int)
    case cannotAffordSharah
    case sharahNotAllowedByPolicy
    case unknownOffer
    case offerAlreadyResolved
    case notTheOfferRecipient
}

/// The game, as a value you can hold, copy and assert against.
///
/// No views, no timers, no animation: a caller drives it one action at a time
/// and reads `phase` to know what it wants next. Responsibilities live in their
/// own modules — `HandEvaluator` and `HandComparator` decide hands,
/// `BettingRules` decides bets, `Settlement` moves money, `SharahPolicy` holds
/// the negotiation knobs that SPEC.md has not locked yet — and this type is
/// the state machine that sequences them.
///
/// Private hands are private: `participation` is not exposed. A caller reads a
/// hand through `hand(of:asSeenBy:)`, which answers nil for an opponent's
/// hidden cards, and an AI is handed only a `PublicTableView`.
public struct GameEngine: Sendable {
    public private(set) var players: [PlayerID: Player]
    public private(set) var seating: [Seat: PlayerID]
    public private(set) var phase: GamePhase = .waitingForPlayers
    public private(set) var offers: [SharahOffer] = []
    /// Rounds completed so far.
    public private(set) var roundIndex = 0
    /// This round's players, in the order they act.
    public private(set) var turnOrder: [PlayerID] = []
    /// The largest bet committed this round, by anyone, still in the round or
    /// not — which is what settlement pays out (SPEC.md §7).
    public private(set) var highestBet = 0
    public private(set) var topBettor: PlayerID?
    public private(set) var lastResult: RoundResult?

    /// The rules SPEC.md leaves open. See `GamePolicy`.
    public let policy: GamePolicy

    public var sharahPolicy: SharahPolicy { policy.sharah }

    /// Cards left after the deal. With fewer than thirteen players they stay
    /// here, unused (SPEC.md §3).
    public private(set) var undealtCards = 0

    private var participation: [PlayerID: RoundParticipation] = [:]
    private var rng: RandomGenerator
    /// The seat that started the last round. The next round starts at the
    /// first active seat to its right, so the deal moves round the table even
    /// when a seat has been eliminated in between.
    private var lastStartingSeat: Seat?

    public init(
        players: [Player],
        policy: GamePolicy = .standard,
        seed: UInt64? = nil
    ) {
        precondition(players.count >= 1, "a table needs at least one player")
        precondition(
            players.count <= GameRules.maxPlayers,
            "one deck seats at most \(GameRules.maxPlayers) players, got \(players.count)"
        )
        precondition(
            Set(players.map(\.seat)).count == players.count,
            "two players cannot share a seat"
        )
        self.players = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        self.seating = Dictionary(uniqueKeysWithValues: players.map { ($0.seat, $0.id) })
        self.policy = policy
        self.rng = RandomGenerator(seed: seed)
    }

    // MARK: - Reading the table

    public func player(at seat: Seat) -> Player? {
        seating[seat].flatMap { players[$0] }
    }

    public func seat(of id: PlayerID) -> Seat? { players[id]?.seat }

    /// Everyone at the table, by seat.
    public var roster: [Player] {
        players.values.sorted { $0.seat < $1.seat }
    }

    /// Players who can take a seat in a round: not eliminated, money left.
    public var activePlayers: [Player] {
        roster.filter(\.isActive)
    }

    /// Players still in the current round, in turn order.
    public var playersInRound: [PlayerID] {
        turnOrder.filter { participation[$0]?.isInRound == true }
    }

    /// Players ranked by balance, richest first; ties by name for stability.
    public var leaderboard: [Player] {
        players.values.sorted {
            $0.balance != $1.balance ? $0.balance > $1.balance : $0.name < $1.name
        }
    }

    public func bet(of id: PlayerID) -> Int { participation[id]?.bet ?? 0 }

    public func standing(of id: PlayerID) -> RoundStanding? { participation[id]?.standing }

    /// Money this player can put behind a Sharah offer: their balance less
    /// whatever they already have on the round (SPEC.md §12).
    ///
    /// A bet is at risk until settlement, so it cannot be promised twice. This
    /// is also what keeps a Sharah payment from ever driving a balance
    /// negative, and it leaves an all-in player with nothing to buy anyone out
    /// with.
    public func availableBalance(of id: PlayerID) -> Int {
        max(0, (players[id]?.balance ?? 0) - bet(of: id))
    }

    /// Every ordinary bet this player may make: any multiple of 500 from 500 up
    /// to what they can afford. What anyone else has bet does not come into it.
    public func betRange(for id: PlayerID) -> BetRange {
        guard let balance = players[id]?.balance else { return .empty }
        return BettingRules.range(balance: balance)
    }

    /// Amounts the player whose turn it is may commit, smallest first, capped
    /// for a picker.
    public func legalBetAmounts(for id: PlayerID, limit: Int = 120) -> [Int] {
        guard let balance = players[id]?.balance else { return [] }
        return BettingRules.legalAmounts(balance: balance, limit: limit)
    }

    /// Whether this player may take `action` on their turn.
    public func isLegal(_ action: BetAction, for id: PlayerID) -> Bool {
        guard let balance = players[id]?.balance else { return false }
        return BettingRules.isLegal(action, balance: balance)
    }

    /// Whether a round can be dealt: a game that is over, or a table with
    /// fewer than two players holding money, cannot.
    public var canStartRound: Bool {
        switch phase {
        case .waitingForPlayers, .roundOver:
            return activePlayers.count >= GameRules.minPlayers
        default:
            return false
        }
    }

    // MARK: - Private information

    /// A hand, if `viewer` is entitled to see it.
    ///
    /// Your own hand, always. An opponent's hand only once the showdown has
    /// revealed it — and a folded or bought-out player's hand never, in any
    /// phase (SPEC.md §4, §8, §9).
    public func hand(of id: PlayerID, asSeenBy viewer: PlayerID) -> Hand? {
        guard let participant = participation[id] else { return nil }
        if id == viewer { return participant.hand }
        guard phase.handsAreRevealed, participant.isInRound else { return nil }
        return participant.hand
    }

    /// Hands that are face up: the showdown's players, once it has happened.
    public var revealedHands: [PlayerID: Hand] {
        guard phase.handsAreRevealed else { return [:] }
        return participation.filter { $0.value.isInRound }.mapValues(\.hand)
    }

    /// The table as `viewer` sees it. The only input an AI is given.
    public func publicView(for viewer: PlayerID?) -> PublicTableView {
        let ordered = turnOrder.isEmpty ? roster.map(\.id) : turnOrder
        let views: [PublicPlayerView] = ordered.compactMap { id in
            guard let player = players[id] else { return nil }
            let seen = viewer.flatMap { hand(of: id, asSeenBy: $0) }
            return PublicPlayerView(
                id: id,
                name: player.name,
                seat: player.seat,
                balance: player.balance,
                bet: bet(of: id),
                standing: participation[id]?.standing ?? .yetToAct,
                isEliminated: player.isEliminated,
                isTopBettor: id == topBettor,
                hand: seen
            )
        }
        return PublicTableView(
            viewer: viewer,
            phase: phase,
            roundIndex: roundIndex,
            players: views,
            highestBet: highestBet,
            topBettor: topBettor,
            offers: sharahPolicy.offersArePublic ? offers : offers.filter { $0.from == viewer || $0.to == viewer }
        )
    }

    // MARK: - Dealing

    /// Shuffles and deals four cards to every active player, one card at a
    /// time, right to left from the round's starting seat (SPEC.md §2).
    public mutating func startRound() throws {
        switch phase {
        case .waitingForPlayers, .roundOver: break
        default: throw GameError.wrongPhase
        }

        let seated = activePlayers
        guard seated.count >= GameRules.minPlayers else { throw GameError.notEnoughPlayers }
        guard seated.count <= GameRules.maxPlayers else { throw GameError.tooManyPlayers }

        let seats = seated.map(\.seat)
        guard let start = GameRules.nextStartingSeat(after: lastStartingSeat, among: seats) else {
            throw GameError.notEnoughPlayers
        }
        lastStartingSeat = start
        turnOrder = GameRules.turnOrder(seats: seats, startingAt: start).compactMap { seating[$0] }

        var deck = Deck()
        deck.shuffle(using: &rng)

        // One card each, round the table, four times over — not four cards to
        // one player at a time, so the order a seat receives cards in matches
        // a physical deal.
        var dealt: [PlayerID: [Card]] = [:]
        for _ in 0..<GameRules.handSize {
            for id in turnOrder {
                guard let card = deck.dealOne() else { break }
                dealt[id, default: []].append(card)
            }
        }

        participation = dealt.mapValues { RoundParticipation(hand: Hand(cards: $0)) }
        undealtCards = deck.count
        offers = []
        highestBet = 0
        topBettor = nil
        phase = .dealing
    }

    /// Cards are down and every player has seen their own.
    public mutating func finishDealing() throws {
        guard case .dealing = phase else { throw GameError.wrongPhase }
        phase = .privateHands
    }

    /// Opens betting with the round's starting player.
    public mutating func beginBetting() throws {
        guard case .privateHands = phase else { throw GameError.wrongPhase }
        guard let first = turnOrder.first else { throw GameError.notEnoughPlayers }
        phase = .betting(turn: first)
    }

    // MARK: - Betting

    /// Takes the player's one turn: fold, match, raise or go all-in.
    @discardableResult
    public mutating func act(_ action: BetAction, by id: PlayerID) throws -> Int {
        try requireTurn(of: id)
        guard let balance = players[id]?.balance,
              let cost = BettingRules.cost(of: action, balance: balance)
        else { throw GameError.illegalAction(action) }

        if action == .fold {
            participation[id]?.bet = 0
            participation[id]?.standing = .folded
        } else {
            commit(cost, by: id)
        }
        advanceTurn()
        return cost
    }

    /// Commits a bare amount, for a caller that works in amounts rather than
    /// actions. Must be one of `legalBetAmounts(for:)`.
    public mutating func bet(_ amount: Int, by id: PlayerID) throws {
        try requireTurn(of: id)
        guard let balance = players[id]?.balance,
              BettingRules.isLegal(amount: amount, balance: balance)
        else { throw GameError.illegalBet(amount) }

        commit(amount, by: id)
        advanceTurn()
    }

    /// Folds. Always legal on your turn, and costs nothing.
    public mutating func fold(_ id: PlayerID) throws {
        try act(.fold, by: id)
    }

    private mutating func commit(_ amount: Int, by id: PlayerID) {
        participation[id]?.bet = amount
        participation[id]?.standing = .committed
        if amount > highestBet {
            highestBet = amount
            topBettor = id
        }
    }

    private func requireTurn(of id: PlayerID) throws {
        guard case .betting(let turn) = phase else { throw GameError.wrongPhase }
        guard players[id] != nil else { throw GameError.unknownPlayer }
        guard turn == id else { throw GameError.notYourTurn }
    }

    /// Betting is one pass: the round moves on once everyone has acted.
    private mutating func advanceTurn() {
        guard case .betting(let turn) = phase,
              let index = turnOrder.firstIndex(of: turn)
        else { return }

        let next = index + 1
        phase = next < turnOrder.count ? .betting(turn: turnOrder[next]) : .negotiation
    }

    // MARK: - Sharah

    /// Offers `to` money to leave the round. Enforces only what SPEC.md §9
    /// locks; everything still open lives in `sharahPolicy`.
    @discardableResult
    public mutating func offerSharah(_ amount: Int, from: PlayerID, to: PlayerID) throws -> UUID {
        guard case .negotiation = phase else { throw GameError.wrongPhase }
        guard players[from] != nil, players[to] != nil else { throw GameError.unknownPlayer }
        guard from != to else { throw GameError.cannotOfferToSelf }
        guard participation[from]?.isInRound == true,
              participation[to]?.isInRound == true
        else { throw GameError.notInRound }
        guard amount > 0 else { throw GameError.illegalSharahAmount(amount) }
        guard amount <= availableBalance(of: from) else { throw GameError.cannotAffordSharah }

        if sharahPolicy.onlyTopBettorMayBeOffered, to != topBettor {
            throw GameError.sharahNotAllowedByPolicy
        }
        if sharahPolicy.onlyTopBettorMayOffer, from != topBettor {
            throw GameError.sharahNotAllowedByPolicy
        }
        if let limit = sharahPolicy.maxPendingOffersPerSender,
           offers.filter({ $0.from == from && $0.isPending }).count >= limit {
            throw GameError.sharahNotAllowedByPolicy
        }

        let offer = SharahOffer(from: from, to: to, amount: amount)
        offers.append(offer)
        return offer.id
    }

    /// The recipient's call. Accepting moves the money at once and takes them
    /// out of the round with their cards unseen; their bet is neither lost nor
    /// refunded, and they cannot come back.
    public mutating func respondToSharah(_ offerID: UUID, accept: Bool, by id: PlayerID) throws {
        guard case .negotiation = phase else { throw GameError.wrongPhase }
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else { throw GameError.unknownOffer }
        guard offers[index].isPending else { throw GameError.offerAlreadyResolved }
        guard offers[index].to == id else { throw GameError.notTheOfferRecipient }

        guard accept else {
            offers[index].state = .rejected
            return
        }

        let offer = offers[index]
        guard participation[offer.to]?.isInRound == true else { throw GameError.notInRound }
        guard offer.amount <= availableBalance(of: offer.from) else { throw GameError.cannotAffordSharah }

        players[offer.from]?.balance -= offer.amount
        players[offer.to]?.balance += offer.amount
        participation[offer.to]?.standing = .boughtOut
        offers[index].state = .accepted
    }

    // MARK: - Showdown, settlement, game end

    /// Ends negotiation and turns the remaining hands face up. No money moves.
    public mutating func closeNegotiation() throws {
        guard case .negotiation = phase else { throw GameError.wrongPhase }
        phase = .showdown
    }

    /// Moves the round's money: the winners collect the highest bet, every
    /// other player at the showdown pays their own bet.
    @discardableResult
    public mutating func settle() throws -> SettlementLedger {
        guard case .showdown = phase else { throw GameError.wrongPhase }

        let showdown: [(id: PlayerID, hand: Hand)] = turnOrder.compactMap { id in
            guard let participant = participation[id], participant.isInRound else { return nil }
            return (id, participant.hand)
        }
        let bets = participation.mapValues(\.bet).filter { $0.value > 0 }
        let ledger = Settlement.settle(showdown: showdown, bets: bets)

        for (id, change) in ledger.netChange {
            players[id]?.balance += change
        }

        lastResult = RoundResult(
            roundIndex: roundIndex,
            revealedHands: Dictionary(uniqueKeysWithValues: showdown.map { ($0.id, $0.hand) }),
            bets: bets,
            ledger: ledger,
            acceptedOffers: offers.filter { $0.state == .accepted },
            eliminated: [],
            gameWinner: nil
        )
        phase = .settlement
        return ledger
    }

    /// Eliminates anyone left with nothing and checks for a game winner.
    @discardableResult
    public mutating func checkGameEnd() throws -> RoundResult {
        guard case .settlement = phase, let settled = lastResult else { throw GameError.wrongPhase }

        let eliminated = Settlement.eliminated(among: roster)
        for id in eliminated { players[id]?.isEliminated = true }

        let winner = Settlement.gameWinner(among: roster, turnOrder: turnOrder)

        let result = RoundResult(
            roundIndex: settled.roundIndex,
            revealedHands: settled.revealedHands,
            bets: settled.bets,
            ledger: settled.ledger,
            acceptedOffers: settled.acceptedOffers,
            eliminated: eliminated,
            gameWinner: winner
        )
        lastResult = result
        roundIndex += 1
        phase = winner.map(GamePhase.gameOver) ?? .roundOver
        return result
    }

    /// Showdown, settlement and the game-end check in one call, for a caller
    /// that does not need to stop in between.
    @discardableResult
    public mutating func endRound() throws -> RoundResult {
        if case .negotiation = phase { try closeNegotiation() }
        try settle()
        return try checkGameEnd()
    }
}
