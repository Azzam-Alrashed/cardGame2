import Foundation

/// A bid from an entrant to buy their way out of the round.
///
/// Non-top-bettors who are still in the round may offer coins to the top
/// bettor in exchange for withdrawing. Offers are final once sent, and the top
/// bettor's accept/reject is final once made. An accepted offer is only
/// actually paid if the top bettor goes on to win the round.
public struct Offer: Identifiable, Hashable, Sendable {
    public enum Resolution: String, Hashable, Sendable {
        case accepted
        case rejected
    }

    public let id: UUID
    public let sender: PlayerID
    public let coins: Int
    public var resolution: Resolution?

    public init(id: UUID = UUID(), sender: PlayerID, coins: Int, resolution: Resolution? = nil) {
        self.id = id
        self.sender = sender
        self.coins = coins
        self.resolution = resolution
    }

    public var isPending: Bool { resolution == nil }
}
