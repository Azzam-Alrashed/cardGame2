import XCTest
@testable import CardGame

/// One standard 52-card poker deck, and the rank order everything else rests
/// on (SPEC.md §2).
final class DeckTests: XCTestCase {

    func testDeckHolds52UniqueCards() {
        let deck = Deck()
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck.cards).count, 52, "the deck holds a duplicate card")
    }

    func testDeckHasThirteenRanksInFourSuits() {
        XCTAssertEqual(Rank.allCases.count, 13)
        XCTAssertEqual(Suit.allCases.count, 4)
        for suit in Suit.allCases {
            let ofSuit = Deck.all.filter { $0.suit == suit }
            XCTAssertEqual(ofSuit.count, 13, "\(suit) is not a full suit")
            XCTAssertEqual(Set(ofSuit.map(\.rank)).count, 13)
        }
        for rank in Rank.allCases {
            XCTAssertEqual(Deck.all.filter { $0.rank == rank }.count, 4, "\(rank) has the wrong count")
        }
    }

    func testRankOrder() {
        let expected: [Rank] = [.ace, .king, .queen, .jack, .ten, .nine, .eight, .seven, .six, .five, .four, .three, .two]
        XCTAssertEqual(Rank.descending, expected)
        XCTAssertGreaterThan(Rank.ace, Rank.king)
        XCTAssertGreaterThan(Rank.ten, Rank.nine)
        XCTAssertGreaterThan(Rank.three, Rank.two)
        XCTAssertEqual(Rank.allCases.max(), .ace)
        XCTAssertEqual(Rank.allCases.min(), .two)
    }

    func testThirteenPlayersIsExactlyOneDeck() {
        XCTAssertEqual(GameRules.maxPlayers, 13)
        XCTAssertEqual(GameRules.maxPlayers * GameRules.handSize, 52)
    }

    func testDealingTakesFromTheTop() {
        var deck = Deck()
        let top = Array(deck.cards.prefix(4))
        XCTAssertEqual(deck.deal(4), top)
        XCTAssertEqual(deck.count, 48)
    }

    func testShuffleIsReproducibleFromASeed() {
        var first = Deck(), second = Deck()
        var a = RandomGenerator(seed: 99), b = RandomGenerator(seed: 99)
        first.shuffle(using: &a)
        second.shuffle(using: &b)
        XCTAssertEqual(first.cards, second.cards)
        XCTAssertNotEqual(first.cards, Deck.all, "the shuffle did nothing")
    }

    /// Suits are identity only, so nothing in the engine may order two cards
    /// by suit. The old `Suit.strength` tiebreak is gone.
    func testSuitsCarryNoStrength() {
        let ranks = Deck.all.filter { $0.rank == .ace }
        XCTAssertEqual(Set(ranks.map(\.rank)).count, 1)
        XCTAssertTrue(HandComparator.isTie(
            hand(.ace, .king, .queen, .jack),
            Hand(cards: [Card(.ace, .clubs), Card(.king, .diamonds), Card(.queen, .spades), Card(.jack, .hearts)])
        ))
    }
}
