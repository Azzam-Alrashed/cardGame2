import Foundation

/// The four ranks in play. The raw value is the rank's contribution to a
/// scoring group (see `Hand.score`); a lone card of the rank is worth a tenth
/// of this.
public enum Rank: Int, CaseIterable, Comparable, Hashable, Sendable {
    case jack = 100
    case queen = 200
    case king = 300
    case ace = 400

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Points for a card of this rank that is not part of a group.
    public var singleValue: Int { rawValue / 10 }
}

public enum Suit: String, CaseIterable, Hashable, Sendable {
    case spades, clubs, hearts, diamonds

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .clubs: return "♣"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        }
    }

    /// Suits never contribute to a hand's score — this only settles hands that
    /// are otherwise identical. ♠ > ♣ > ♥ > ♦.
    public var strength: Int {
        switch self {
        case .spades: return 4
        case .clubs: return 3
        case .hearts: return 2
        case .diamonds: return 1
        }
    }
}

extension Suit: Comparable {
    public static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.strength < rhs.strength
    }
}

public struct Card: Hashable, Identifiable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    public var id: String { "\(rank)_\(suit)" }

    /// Asset-catalog name for this card's face, e.g. `ace_spades`.
    public var imageName: String { "\(rank)_\(suit.rawValue)" }
}

/// Cards order by rank, then by suit for cards of the same rank.
extension Card: Comparable {
    public static func < (lhs: Card, rhs: Card) -> Bool {
        lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.suit < rhs.suit
    }
}

extension Card: CustomStringConvertible {
    public var description: String {
        let letter: String
        switch rank {
        case .ace: letter = "A"
        case .king: letter = "K"
        case .queen: letter = "Q"
        case .jack: letter = "J"
        }
        return letter + suit.symbol
    }
}

/// The 16-card deck: every rank in every suit.
public struct Deck: Sendable {
    public private(set) var cards: [Card]

    public static let all: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card($0, suit) }
    }

    public init(cards: [Card] = Deck.all) {
        self.cards = cards
    }

    public mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        cards.shuffle(using: &generator)
    }

    /// Removes and returns the next `count` cards from the top of the deck.
    public mutating func deal(_ count: Int) -> [Card] {
        precondition(count <= cards.count, "dealt \(count) cards from a deck of \(cards.count)")
        let hand = Array(cards.prefix(count))
        cards.removeFirst(count)
        return hand
    }
}
