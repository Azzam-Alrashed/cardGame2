import Foundation

/// A player's four private cards, with the ranking they compare on.
///
/// There is no score here. The old engine added a combination's base value to
/// its rank values and sorted on the total, which let different combinations
/// collide on one number; SPEC.md §6 replaces that with a strict hierarchy,
/// evaluated by `HandEvaluator` and compared by `HandComparator`.
public struct Hand: Hashable, Sendable {
    /// The cards as they were dealt.
    public let cards: [Card]
    /// The same cards, strongest rank first — for drawing a fan, not for
    /// comparing hands.
    public let sortedCards: [Card]
    public let ranking: HandRanking

    public init(cards: [Card]) {
        self.cards = cards
        self.sortedCards = cards.sorted(by: Card.strongestFirst)
        self.ranking = HandEvaluator.evaluate(cards)
    }

    public var combination: Combination { ranking.combination }

    /// The ranks that decide this hand, most significant first.
    public var orderedRanks: [Rank] { ranking.orderedRanks }

    /// Two hands are the same hand when they hold the same cards. This is
    /// identity, not strength — `HandComparator.isTie` is strength.
    public static func == (lhs: Hand, rhs: Hand) -> Bool {
        lhs.sortedCards == rhs.sortedCards
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sortedCards)
    }
}

extension Hand: CustomStringConvertible {
    public var description: String {
        sortedCards.map(\.description).joined(separator: " ")
    }
}
