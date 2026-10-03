import Foundation

/// The thirteen ranks of a standard deck.
///
/// The raw value is the rank's **strength** and nothing else — there is no
/// scoring table in this game, so a rank carries no points. Strength is the
/// only axis a card is ever judged on (SPEC.md §2).
///
/// A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2
public enum Rank: Int, CaseIterable, Comparable, Hashable, Sendable {
    case two = 2
    case three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    /// Where the rank sits in the order above. Higher is stronger.
    public var strength: Int { rawValue }

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.strength < rhs.strength
    }

    /// Strongest first, which is the direction every comparison walks.
    public static let descending: [Rank] = allCases.sorted(by: >)

    public var label: String {
        switch self {
        case .ace: return "A"
        case .king: return "K"
        case .queen: return "Q"
        case .jack: return "J"
        case .ten: return "10"
        case .nine: return "9"
        case .eight: return "8"
        case .seven: return "7"
        case .six: return "6"
        case .five: return "5"
        case .four: return "4"
        case .three: return "3"
        case .two: return "2"
        }
    }

    /// Lower-case name, as used in asset-catalog image names: `ace`, `ten`.
    public var assetName: String { String(describing: self) }
}

/// The four suits.
///
/// Suits are card identity only — which physical card this is, and which piece
/// of art to draw. They have **zero** effect on anything else (SPEC.md §2), so
/// this type is deliberately *not* `Comparable` and carries no strength: there
/// is nothing in the game that may order two cards by suit, including ties.
public enum Suit: String, CaseIterable, Hashable, Sendable {
    case spades, hearts, diamonds, clubs

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }

    /// Declaration order. For laying cards out on screen in a stable order —
    /// never for comparing them.
    var displayOrder: Int {
        Suit.allCases.firstIndex(of: self) ?? 0
    }
}

public struct Card: Hashable, Identifiable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    public var id: String { "\(rank.assetName)_\(suit.rawValue)" }

    /// Asset-catalog name for this card's face, e.g. `ace_spades`.
    public var imageName: String { id }

    /// Strongest rank first. Cards of equal rank fall back to suit
    /// *declaration* order purely so a fan of cards draws the same way twice;
    /// no comparison in the game may use it.
    public static func strongestFirst(_ lhs: Card, _ rhs: Card) -> Bool {
        lhs.rank != rhs.rank
            ? lhs.rank > rhs.rank
            : lhs.suit.displayOrder < rhs.suit.displayOrder
    }
}

extension Card: CustomStringConvertible {
    public var description: String { rank.label + suit.symbol }
}

/// One standard 52-card poker deck: every rank in every suit.
public struct Deck: Sendable {
    public private(set) var cards: [Card]

    public static let all: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card($0, suit) }
    }

    public init(cards: [Card] = Deck.all) {
        self.cards = cards
    }

    public var count: Int { cards.count }

    public mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        cards.shuffle(using: &generator)
    }

    /// Removes and returns the top card, or nil when the deck is spent.
    public mutating func dealOne() -> Card? {
        cards.isEmpty ? nil : cards.removeFirst()
    }

    /// Removes and returns the next `count` cards from the top.
    public mutating func deal(_ count: Int) -> [Card] {
        precondition(count <= cards.count, "dealt \(count) cards from a deck of \(cards.count)")
        let dealt = Array(cards.prefix(count))
        cards.removeFirst(count)
        return dealt
    }
}
