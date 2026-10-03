import Foundation

/// A place at the table, numbered from 0.
///
/// The old engine had four compass cases, which cannot describe a table of up
/// to thirteen (SPEC.md §3). Seats are now indices; the four compass names
/// survive as conveniences for a four-handed table and for the existing UI
/// layout, where seat 0 is the near edge.
///
/// Index order is right-to-left round the table — see `GameRules.seats(for:)`.
public struct Seat: Hashable, Comparable, Identifiable, Sendable {
    public let index: Int

    public init(_ index: Int) {
        precondition(index >= 0, "seat index cannot be negative")
        self.index = index
    }

    public var id: Int { index }

    public static func < (lhs: Seat, rhs: Seat) -> Bool { lhs.index < rhs.index }

    public static let south = Seat(0)
    public static let east = Seat(1)
    public static let north = Seat(2)
    public static let west = Seat(3)

    public var label: String { "Seat \(index + 1)" }
}

public struct PlayerID: Hashable, Comparable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

public struct Player: Identifiable, Hashable, Sendable {
    public let id: PlayerID
    public var name: String
    /// Asset-catalog name for the avatar.
    public var avatarName: String
    public var seat: Seat
    /// Money, persistent between rounds. Always an integer (SPEC.md §7).
    public var balance: Int
    /// True for the player this device is controlled by; the rest are driven
    /// by `AIStrategy`.
    public var isHuman: Bool
    /// Out of the game for good: balance reached zero (SPEC.md §5).
    public var isEliminated: Bool

    public init(
        id: PlayerID,
        name: String,
        avatarName: String = "profile-image",
        seat: Seat,
        balance: Int = GameRules.startingBalance,
        isHuman: Bool = false,
        isEliminated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.avatarName = avatarName
        self.seat = seat
        self.balance = balance
        self.isHuman = isHuman
        self.isEliminated = isEliminated
    }

    /// Can take a seat in the next round.
    public var isActive: Bool { !isEliminated && balance > 0 }

    /// Has won the game (SPEC.md §13).
    public var hasReachedTarget: Bool { balance >= GameRules.targetBalance }
}

/// Where a player stands in the current round.
public enum RoundStanding: Hashable, Sendable {
    /// Dealt in, has not acted yet.
    case yetToAct
    /// In the round for the bet they committed.
    case committed
    /// Folded. No money committed, no showdown, cards stay hidden (SPEC.md §8).
    case folded
    /// Accepted a Sharah offer and left. Cards stay hidden, the bet is not
    /// lost, and they cannot return (SPEC.md §9).
    case boughtOut
}

/// One player's involvement in one round.
public struct RoundParticipation: Hashable, Sendable {
    /// Private to its owner until the showdown reveals it — and never revealed
    /// for a player who folded or was bought out.
    public var hand: Hand
    /// Money put on this round. Not refunded on a Sharah exit, but not lost
    /// either.
    public var bet: Int
    public var standing: RoundStanding

    public init(hand: Hand, bet: Int = 0, standing: RoundStanding = .yetToAct) {
        self.hand = hand
        self.bet = bet
        self.standing = standing
    }

    /// Still in the round, heading for the showdown.
    public var isInRound: Bool { standing == .committed }

    /// Left the round without revealing: folded or bought out.
    public var hasLeftConcealed: Bool {
        standing == .folded || standing == .boughtOut
    }
}
