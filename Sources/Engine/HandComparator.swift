import Foundation

/// The authority on which of two hands is stronger.
///
/// Nothing else in the game is allowed to decide a showdown: there is no
/// numeric hand score to sort on, and `Hand` deliberately does not conform to
/// `Comparable`, so every comparison comes through here (SPEC.md §6).
public enum HandComparator {

    /// How `lhs` stands against `rhs`.
    public static func compare(_ lhs: Hand, _ rhs: Hand) -> ComparisonResult {
        compare(lhs.ranking, rhs.ranking)
    }

    public static func compare(_ lhs: HandRanking, _ rhs: HandRanking) -> ComparisonResult {
        if lhs.combination != rhs.combination {
            return lhs.combination < rhs.combination ? .orderedAscending : .orderedDescending
        }
        for (left, right) in zip(lhs.orderedRanks, rhs.orderedRanks) where left != right {
            return left < right ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    public static func beats(_ lhs: Hand, _ rhs: Hand) -> Bool {
        compare(lhs, rhs) == .orderedDescending
    }

    /// A true tie: the complete rank comparison is identical. Suits are never
    /// consulted, so two hands holding the same ranks in different suits tie.
    public static func isTie(_ lhs: Hand, _ rhs: Hand) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }

    /// Every entry tied for the strongest hand, in the order they were given —
    /// which callers pass in turn order, because that is what decides a tie
    /// remainder (SPEC.md §7).
    public static func strongest<ID>(among contenders: [(id: ID, hand: Hand)]) -> [ID] {
        guard let best = contenders.max(by: { compare($0.hand, $1.hand) == .orderedAscending })?.hand
        else { return [] }
        return contenders.filter { compare($0.hand, best) == .orderedSame }.map(\.id)
    }
}
