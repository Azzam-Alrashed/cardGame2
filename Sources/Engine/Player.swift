import Foundation

/// Where a player sits, which is also where their cards and bet bubble are
/// drawn. `.south` is the human player in a single-device game.
public enum Seat: Int, CaseIterable, Hashable, Sendable {
    case south = 0
    case east = 1
    case north = 2
    case west = 3
}

public struct PlayerID: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct Player: Identifiable, Hashable, Sendable {
    public let id: PlayerID
    public var name: String
    /// Asset-catalog name for the avatar.
    public var avatarName: String
    public var seat: Seat
    public var coins: Int
    /// True for the player this device is controlled by; the rest are driven
    /// by `AIStrategy`.
    public var isHuman: Bool

    public init(
        id: PlayerID,
        name: String,
        avatarName: String,
        seat: Seat,
        coins: Int = GameRules.startingCoins,
        isHuman: Bool = false
    ) {
        self.id = id
        self.name = name
        self.avatarName = avatarName
        self.seat = seat
        self.coins = coins
        self.isHuman = isHuman
    }
}

/// What a player is doing in the current round.
public struct RoundParticipation: Hashable, Sendable {
    public var hand: Hand
    /// Coins committed this round. Zero means they withdrew or never entered.
    public var bet: Int = 0
    public var hasWithdrawn: Bool = false

    /// A player is in the round once they have money on it and have not pulled out.
    public var isEntrant: Bool { bet > 0 && !hasWithdrawn }

    public init(hand: Hand, bet: Int = 0, hasWithdrawn: Bool = false) {
        self.hand = hand
        self.bet = bet
        self.hasWithdrawn = hasWithdrawn
    }
}
