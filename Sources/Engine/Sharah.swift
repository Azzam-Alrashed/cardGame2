import Foundation

/// An offer of money to another player to leave the round (SPEC.md §9).
///
/// Sharah is economic only. It never touches card strength, the comparison in
/// `HandComparator`, or who would have won the showdown. On acceptance the
/// money moves immediately, the accepter leaves with their cards unseen, their
/// bet is neither lost nor refunded, and they cannot return.
public struct SharahOffer: Identifiable, Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case pending, accepted, rejected
    }

    public let id: UUID
    /// Who pays.
    public let from: PlayerID
    /// Who is being asked to leave.
    public let to: PlayerID
    public let amount: Int
    public var state: State

    public init(
        id: UUID = UUID(),
        from: PlayerID,
        to: PlayerID,
        amount: Int,
        state: State = .pending
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.amount = amount
        self.state = state
    }

    public var isPending: Bool { state == .pending }
}

/// The parts of Sharah that SPEC.md §8 still marks as not fully locked.
///
/// These are deliberately isolated here rather than hard-coded into the engine,
/// because the rules are not settled: who may offer to whom, whether offers
/// are public, whether several may be open at once. The defaults are
/// permissive — the engine enforces only what §9 locks down — so that pinning
/// a rule later is a change to this type and nothing else.
public struct SharahPolicy: Hashable, Sendable {
    /// OPEN: when true, only the round's top bettor may be offered money to
    /// leave. Default false — any player in the round may be.
    public var onlyTopBettorMayBeOffered: Bool
    /// OPEN: when true, only the top bettor may send offers. Default false.
    public var onlyTopBettorMayOffer: Bool
    /// OPEN: how many offers one player may have pending at a time. Nil is
    /// unlimited, which is the default.
    public var maxPendingOffersPerSender: Int?
    /// OPEN: whether every player sees the offers. Default true — the UI shows
    /// them. Does not affect settlement either way.
    public var offersArePublic: Bool

    public init(
        onlyTopBettorMayBeOffered: Bool = false,
        onlyTopBettorMayOffer: Bool = false,
        maxPendingOffersPerSender: Int? = nil,
        offersArePublic: Bool = true
    ) {
        self.onlyTopBettorMayBeOffered = onlyTopBettorMayBeOffered
        self.onlyTopBettorMayOffer = onlyTopBettorMayOffer
        self.maxPendingOffersPerSender = maxPendingOffersPerSender
        self.offersArePublic = offersArePublic
    }

    public static let standard = SharahPolicy()
}
