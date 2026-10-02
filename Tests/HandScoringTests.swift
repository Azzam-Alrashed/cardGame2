import XCTest
@testable import CardGame

/// Every case here is taken from the worked examples in the original
/// `GameLogic.swift` spec comment.
final class HandScoringTests: XCTestCase {

    private func hand(_ cards: [(Rank, Suit)]) -> Hand {
        Hand(cards: cards.map { Card($0.0, $0.1) })
    }

    func testFourOfAKind() {
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.ace, .diamonds)]).score, 4400)
        XCTAssertEqual(hand([(.king, .spades), (.king, .clubs), (.king, .hearts), (.king, .diamonds)]).score, 4300)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.queen, .hearts), (.queen, .diamonds)]).score, 4200)
        XCTAssertEqual(hand([(.jack, .spades), (.jack, .clubs), (.jack, .hearts), (.jack, .diamonds)]).score, 4100)
    }

    func testThreeOfAKindPlusOne() {
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.king, .diamonds)]).score, 3430)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.queen, .diamonds)]).score, 3420)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.jack, .diamonds)]).score, 3410)
        XCTAssertEqual(hand([(.king, .spades), (.king, .clubs), (.king, .hearts), (.ace, .diamonds)]).score, 3340)
        XCTAssertEqual(hand([(.king, .spades), (.king, .clubs), (.king, .hearts), (.queen, .diamonds)]).score, 3320)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.queen, .hearts), (.jack, .diamonds)]).score, 3210)
        XCTAssertEqual(hand([(.jack, .spades), (.jack, .clubs), (.jack, .hearts), (.queen, .diamonds)]).score, 3120)
    }

    func testTwoPair() {
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.king, .hearts), (.king, .diamonds)]).score, 3100)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.queen, .hearts), (.queen, .diamonds)]).score, 3000)
        XCTAssertEqual(hand([(.king, .spades), (.king, .clubs), (.jack, .hearts), (.jack, .diamonds)]).score, 2800)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.jack, .hearts), (.jack, .diamonds)]).score, 2700)
    }

    /// The spec flags this collision explicitly: aces-and-jacks ties with
    /// kings-and-queens.
    func testTwoPairTieFromTheSpec() {
        let acesAndJacks = hand([(.ace, .spades), (.ace, .clubs), (.jack, .hearts), (.jack, .diamonds)])
        let kingsAndQueens = hand([(.king, .spades), (.king, .clubs), (.queen, .hearts), (.queen, .diamonds)])
        XCTAssertEqual(acesAndJacks.score, 2900)
        XCTAssertEqual(kingsAndQueens.score, 2900)
        XCTAssertFalse(acesAndJacks < kingsAndQueens)
        XCTAssertFalse(kingsAndQueens < acesAndJacks)
    }

    func testOnePairPlusTwoLooseCards() {
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.king, .hearts), (.queen, .diamonds)]).score, 2450)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.king, .hearts), (.jack, .diamonds)]).score, 2440)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.queen, .hearts), (.jack, .diamonds)]).score, 2430)
        XCTAssertEqual(hand([(.king, .spades), (.king, .clubs), (.ace, .hearts), (.queen, .diamonds)]).score, 2360)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.ace, .hearts), (.king, .diamonds)]).score, 2270)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.ace, .hearts), (.jack, .diamonds)]).score, 2250)
        XCTAssertEqual(hand([(.queen, .spades), (.queen, .clubs), (.king, .hearts), (.jack, .diamonds)]).score, 2240)
        XCTAssertEqual(hand([(.jack, .spades), (.jack, .clubs), (.ace, .hearts), (.king, .diamonds)]).score, 2170)
        XCTAssertEqual(hand([(.jack, .spades), (.jack, .clubs), (.ace, .hearts), (.queen, .diamonds)]).score, 2160)
        XCTAssertEqual(hand([(.jack, .spades), (.jack, .clubs), (.king, .hearts), (.queen, .diamonds)]).score, 2150)
    }

    func testRainbowIsTheWeakestHand() {
        let rainbow = hand([(.ace, .spades), (.king, .clubs), (.queen, .hearts), (.jack, .diamonds)])
        XCTAssertEqual(rainbow.score, 100)
        XCTAssertEqual(rainbow.combination, .none)
    }

    func testCombinationsAreClassified() {
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.ace, .diamonds)]).combination, .fourOfAKind)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.king, .diamonds)]).combination, .threeOfAKind)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.king, .hearts), (.king, .diamonds)]).combination, .twoPair)
        XCTAssertEqual(hand([(.ace, .spades), (.ace, .clubs), (.king, .hearts), (.queen, .diamonds)]).combination, .pair)
        XCTAssertEqual(hand([(.ace, .spades), (.king, .clubs), (.queen, .hearts), (.jack, .diamonds)]).combination, .none)
    }

    func testSuitsDoNotAffectScore() {
        let spadeHeavy = hand([(.ace, .spades), (.king, .spades), (.queen, .spades), (.jack, .spades)])
        let mixed = hand([(.ace, .hearts), (.king, .clubs), (.queen, .diamonds), (.jack, .spades)])
        XCTAssertEqual(spadeHeavy.score, mixed.score)
    }

    /// Any four-card hand lands between the rainbow and four aces.
    func testScoreBoundsHoldAcrossEveryPossibleHand() {
        var seen = 0
        let deck = Deck.all
        for a in 0..<deck.count {
            for b in (a + 1)..<deck.count {
                for c in (b + 1)..<deck.count {
                    for d in (c + 1)..<deck.count {
                        let h = Hand(cards: [deck[a], deck[b], deck[c], deck[d]])
                        XCTAssertGreaterThanOrEqual(h.score, 100)
                        XCTAssertLessThanOrEqual(h.score, 4400)
                        seen += 1
                    }
                }
            }
        }
        XCTAssertEqual(seen, 1820) // C(16,4)
    }
}
