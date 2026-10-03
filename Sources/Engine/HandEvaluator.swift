import Foundation

/// The five shapes a four-card hand can take, strongest first (SPEC.md §6).
///
/// The raw value is an **ordinal in the hierarchy** — a position, not a score.
/// There is no points table in this game: a stronger type beats a weaker one
/// outright, whatever ranks either hand holds.
public enum Combination: Int, CaseIterable, Comparable, Hashable, Sendable {
    case noMatch = 0
    case onePair = 1
    case twoPairs = 2
    case threeOfAKind = 3
    case fourOfAKind = 4

    public static func < (lhs: Combination, rhs: Combination) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var name: String {
        switch self {
        case .fourOfAKind: return "Four of a kind"
        case .threeOfAKind: return "Three of a kind"
        case .twoPairs: return "Two pairs"
        case .onePair: return "One pair"
        case .noMatch: return "No matching cards"
        }
    }
}

/// Everything about a hand that may decide a round: its combination and the
/// ranks that form it, in the exact order they are compared.
///
/// `orderedRanks` is the comparison key, most significant first:
///
/// | Combination | Key |
/// |---|---|
/// | Four of a kind | quad rank |
/// | Three of a kind | trip rank, then kickers descending |
/// | Two pairs | higher pair, lower pair |
/// | One pair | pair rank, higher kicker, lower kicker |
/// | No matching cards | all four ranks descending |
///
/// Suits are absent from this type by construction, so no comparison built on
/// it can consult them.
public struct HandRanking: Hashable, Comparable, Sendable {
    public let combination: Combination
    public let orderedRanks: [Rank]

    public init(combination: Combination, orderedRanks: [Rank]) {
        self.combination = combination
        self.orderedRanks = orderedRanks
    }

    /// Type first; ranks only when the types match.
    public static func < (lhs: HandRanking, rhs: HandRanking) -> Bool {
        if lhs.combination != rhs.combination { return lhs.combination < rhs.combination }
        for (left, right) in zip(lhs.orderedRanks, rhs.orderedRanks) where left != right {
            return left < right
        }
        return false
    }

    public var description: String {
        combination.name + " — " + orderedRanks.map(\.label).joined(separator: " ")
    }
}

/// Turns four cards into a `HandRanking`.
///
/// One pass: group the cards by rank, sort the groups by size and then by rank,
/// and the group sizes name the combination while the group ranks, flattened,
/// are the comparison key. That ordering produces exactly the sequences
/// SPEC.md §6 lists, including a trips kicker — which one deck can never
/// actually need, since two players cannot hold the same trip rank, but which
/// keeps the comparator total.
public enum HandEvaluator {
    public static func evaluate(_ cards: [Card]) -> HandRanking {
        precondition(
            cards.count == GameRules.handSize,
            "a hand holds exactly \(GameRules.handSize) cards, got \(cards.count)"
        )

        var counts: [Rank: Int] = [:]
        for card in cards { counts[card.rank, default: 0] += 1 }

        // Bigger groups first; equal-sized groups by rank, strongest first.
        let groups = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key > rhs.key
        }

        return HandRanking(
            combination: combination(ofGroupSizes: groups.map(\.value)),
            orderedRanks: groups.map(\.key)
        )
    }

    /// The group sizes of four cards can only be 4, 3+1, 2+2, 2+1+1 or
    /// 1+1+1+1, so the five combinations are complete and mutually exclusive.
    static func combination(ofGroupSizes sizes: [Int]) -> Combination {
        switch (sizes.first ?? 0, sizes.count) {
        case (4, _): return .fourOfAKind
        case (3, _): return .threeOfAKind
        case (2, 2): return .twoPairs
        case (2, _): return .onePair
        default: return .noMatch
        }
    }
}
