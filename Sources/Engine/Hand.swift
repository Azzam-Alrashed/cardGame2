import Foundation

/// The shape of a hand: how its four cards group by rank.
public enum Combination: Int, Comparable, Hashable, Sendable {
    /// Four of a kind.
    case fourOfAKind = 4000
    /// Three of a kind plus one loose card.
    case threeOfAKind = 3000
    /// Two pairs.
    case twoPair = 2400
    /// One pair plus two loose cards.
    case pair = 2000
    /// No two cards share a rank — a "rainbow" A K Q J.
    case none = 0

    public static func < (lhs: Combination, rhs: Combination) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A scored four-card hand.
///
/// Scoring, per the original game's spec:
/// - the combination's base value, plus
/// - the full rank value of every grouped rank, plus
/// - a tenth of the rank value of every loose card.
///
/// So four aces score `4000 + 400 = 4400`, a pair of aces over a pair of kings
/// scores `2400 + 400 + 300 = 3100`, and a rainbow A K Q J scores
/// `40 + 30 + 20 + 10 = 100`. Suits never affect the score.
public struct Hand: Hashable, Sendable {
    public let cards: [Card]

    /// Ranks appearing two or more times, highest first.
    public let groupedRanks: [Rank]
    /// Ranks appearing exactly once, highest first.
    public let looseRanks: [Rank]

    public let combination: Combination
    public let score: Int

    public init(cards: [Card]) {
        precondition(cards.count == 4, "a hand holds exactly 4 cards, got \(cards.count)")
        self.cards = cards

        let counts = Dictionary(grouping: cards, by: \.rank).mapValues(\.count)
        groupedRanks = counts.filter { $0.value > 1 }.keys.sorted(by: >)
        looseRanks = counts.filter { $0.value == 1 }.keys.sorted(by: >)

        let largestGroup = groupedRanks.map { counts[$0] ?? 0 }.max() ?? 0
        switch (largestGroup, groupedRanks.count) {
        case (4, _): combination = .fourOfAKind
        case (3, _): combination = .threeOfAKind
        case (2, 2): combination = .twoPair
        case (2, _): combination = .pair
        default: combination = .none
        }

        score = combination.rawValue
            + groupedRanks.reduce(0) { $0 + $1.rawValue }
            + looseRanks.reduce(0) { $0 + $1.singleValue }
    }
}

extension Hand: Comparable {
    /// Hands compare by score alone. Equal scores are genuine ties — the spec
    /// calls this out: two aces with two jacks and two kings with two queens
    /// both score 2900. `GameEngine` breaks such ties by turn order.
    public static func < (lhs: Hand, rhs: Hand) -> Bool {
        lhs.score < rhs.score
    }
}

extension Hand: CustomStringConvertible {
    public var description: String {
        cards.map(\.description).joined(separator: " ") + " = \(score)"
    }
}
