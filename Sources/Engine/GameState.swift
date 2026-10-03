import Foundation

/// The explicit states a game moves through (SPEC.md §12).
///
/// Every action the engine accepts belongs to exactly one of these, and
/// `GameEngine` rejects anything out of state: no betting after the showdown,
/// no Sharah once the round is over, no second deal, no access to a hidden
/// hand.
///
/// The names map to §12 one for one, with `FOLD / EXIT` being actions taken
/// during `betting` and `negotiation` rather than a state of its own, and
/// `NEXT_ROUND` being `startRound()` out of `roundOver`.
public enum GamePhase: Hashable, Sendable {
    /// No round in progress. The table may still be filling up.
    case waitingForPlayers
    /// Cards are being dealt, one at a time, right to left.
    case dealing
    /// Everyone has four cards and has seen their own. Nobody has acted.
    case privateHands
    /// Waiting for `turn` to fold, match, raise or go all-in.
    case betting(turn: PlayerID)
    /// Bets are final. Players may offer each other money to leave.
    case negotiation
    /// Hands of the remaining players are face up. No money has moved.
    case showdown
    /// The round's money has moved. Awaiting the game-end check.
    case settlement
    /// Round complete. `startRound()` deals the next one.
    case roundOver
    /// Someone reached the target. Nothing further happens.
    case gameOver(winner: PlayerID)

    /// A short name, matching the state list in SPEC.md §12.
    public var name: String {
        switch self {
        case .waitingForPlayers: return "WAITING_FOR_PLAYERS"
        case .dealing: return "DEALING"
        case .privateHands: return "PRIVATE_HAND"
        case .betting: return "BETTING"
        case .negotiation: return "SHARAH"
        case .showdown: return "SHOWDOWN"
        case .settlement: return "SETTLEMENT"
        case .roundOver: return "NEXT_ROUND"
        case .gameOver: return "GAME_OVER"
        }
    }

    /// Whether hands that reached the showdown are face up in this state.
    public var handsAreRevealed: Bool {
        switch self {
        case .showdown, .settlement, .roundOver, .gameOver: return true
        default: return false
        }
    }
}

/// What one player is allowed to know about another (SPEC.md §4, §10).
///
/// `hand` is nil for every opponent until the showdown reveals it, and stays
/// nil for ever for a player who folded or was bought out. The engine builds
/// these; it does not hand out its private participation table, so an AI or a
/// view can only see what a player is entitled to see.
public struct PublicPlayerView: Hashable, Sendable {
    public let id: PlayerID
    public let name: String
    public let seat: Seat
    public let balance: Int
    /// Money this player has committed to the round. A public action.
    public let bet: Int
    public let standing: RoundStanding
    public let isEliminated: Bool
    public let isTopBettor: Bool
    /// The viewer's own hand, or an opponent's once it is revealed. Otherwise
    /// nil — including after a fold or a Sharah exit, which never reveal.
    public let hand: Hand?

    public init(
        id: PlayerID,
        name: String,
        seat: Seat,
        balance: Int,
        bet: Int,
        standing: RoundStanding,
        isEliminated: Bool,
        isTopBettor: Bool,
        hand: Hand?
    ) {
        self.id = id
        self.name = name
        self.seat = seat
        self.balance = balance
        self.bet = bet
        self.standing = standing
        self.isEliminated = isEliminated
        self.isTopBettor = isTopBettor
        self.hand = hand
    }
}

/// The table as one player sees it. This is the only thing `AIStrategy` is
/// given, so an opponent's cards are not reachable from a decision — not by
/// accident and not on purpose.
public struct PublicTableView: Hashable, Sendable {
    public let viewer: PlayerID?
    public let phase: GamePhase
    public let roundIndex: Int
    /// Everyone at the table, in this round's turn order.
    public let players: [PublicPlayerView]
    /// The largest bet committed this round, by anyone, still in or not.
    /// Public information, and a claim rather than evidence — it does not
    /// constrain what anyone else may bet.
    public let highestBet: Int
    public let topBettor: PlayerID?
    /// Sharah offers, which are public actions.
    public let offers: [SharahOffer]

    public init(
        viewer: PlayerID?,
        phase: GamePhase,
        roundIndex: Int,
        players: [PublicPlayerView],
        highestBet: Int,
        topBettor: PlayerID?,
        offers: [SharahOffer]
    ) {
        self.viewer = viewer
        self.phase = phase
        self.roundIndex = roundIndex
        self.players = players
        self.highestBet = highestBet
        self.topBettor = topBettor
        self.offers = offers
    }

    public func player(_ id: PlayerID) -> PublicPlayerView? {
        players.first { $0.id == id }
    }

    /// Everyone but the viewer.
    public var opponents: [PublicPlayerView] {
        players.filter { $0.id != viewer }
    }

    /// Opponents still in the round.
    public var opponentsInRound: [PublicPlayerView] {
        opponents.filter { $0.standing == .committed }
    }

    /// How many opponents have folded or been bought out.
    public var opponentsOut: Int {
        opponents.filter { $0.standing == .folded || $0.standing == .boughtOut }.count
    }
}
