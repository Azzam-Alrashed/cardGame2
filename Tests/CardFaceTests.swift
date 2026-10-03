import XCTest
@testable import CardGame

/// The bug this suite exists for: the catalogue art covers A, K, Q and J only,
/// and a card with no art drew nothing — so a four-card hand could look like
/// one card. Every card in the deck must be drawable.
@MainActor
final class CardFaceTests: XCTestCase {

    func testEveryCardInTheDeckCanBeDrawn() {
        for card in Deck.all {
            XCTAssertTrue(CardFace.canDraw(card), "\(card) would draw as nothing")
        }
    }

    func testNumberCardsCarryAPipForEveryPoint() {
        let expected: [Rank: Int] = [
            .two: 2, .three: 3, .four: 4, .five: 5, .six: 6,
            .seven: 7, .eight: 8, .nine: 9, .ten: 10,
        ]
        for (rank, count) in expected {
            XCTAssertEqual(CardFace.pipLayout(for: rank).count, count, "\(rank) has the wrong pip count")
        }
    }

    func testTheAceAndTheCourtCardsCarryOneMark() {
        for rank in [Rank.ace, .king, .queen, .jack] {
            XCTAssertEqual(CardFace.pipLayout(for: rank).count, 1)
        }
    }

    func testEveryPipSitsInsideTheField() {
        for rank in Rank.allCases {
            for spot in CardFace.pipLayout(for: rank) {
                XCTAssertTrue((0...1).contains(spot.x), "\(rank) has a pip off the card: \(spot)")
                XCTAssertTrue((0...1).contains(spot.y), "\(rank) has a pip off the card: \(spot)")
            }
        }
    }

    /// The ranks the old 16-card deck shipped art for still use it.
    func testTheOriginalArtIsStillUsedWhereItExists() {
        for rank in [Rank.ace, .king, .queen, .jack] {
            for suit in Suit.allCases {
                XCTAssertNotNil(
                    CardFace.artwork(named: Card(rank, suit).imageName),
                    "lost the artwork for \(Card(rank, suit))"
                )
            }
        }
    }

    func testRanksWithoutArtAreTheOnesBeingDrawn() {
        let drawn = Rank.allCases.filter { rank in
            CardFace.artwork(named: Card(rank, .spades).imageName) == nil
        }
        XCTAssertEqual(Set(drawn), Set([.ten, .nine, .eight, .seven, .six, .five, .four, .three, .two]))
    }

    func testSuitColoursAreTheUsualOnes() {
        XCTAssertTrue(Suit.hearts.isRed)
        XCTAssertTrue(Suit.diamonds.isRed)
        XCTAssertFalse(Suit.spades.isRed)
        XCTAssertFalse(Suit.clubs.isRed)
    }
}
