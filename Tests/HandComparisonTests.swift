import XCTest
@testable import CardGame

/// Every case here comes from SPEC.md §5–§7. Suits are never named: the
/// `hand(_:)` helper hands them out arbitrarily, because no comparison may
/// depend on them.
final class HandComparisonTests: XCTestCase {

    private func assertBeats(_ stronger: Hand, _ weaker: Hand, _ note: String = "") {
        XCTAssertTrue(HandComparator.beats(stronger, weaker), "\(stronger) should beat \(weaker). \(note)")
        XCTAssertFalse(HandComparator.beats(weaker, stronger), "\(weaker) should not beat \(stronger). \(note)")
        XCTAssertFalse(HandComparator.isTie(stronger, weaker))
    }

    // MARK: - Classification

    func testEveryShapeIsClassified() {
        XCTAssertEqual(hand(.ace, .ace, .ace, .ace).combination, .fourOfAKind)
        XCTAssertEqual(hand(.jack, .jack, .jack, .four).combination, .threeOfAKind)
        XCTAssertEqual(hand(.ace, .ace, .king, .king).combination, .twoPairs)
        XCTAssertEqual(hand(.queen, .queen, .ace, .king).combination, .onePair)
        XCTAssertEqual(hand(.ace, .king, .ten, .nine).combination, .noMatch)
    }

    func testComparisonKeyIsOrderedForComparison() {
        XCTAssertEqual(hand(.ace, .ace, .ace, .ace).orderedRanks, [.ace])
        XCTAssertEqual(hand(.jack, .jack, .jack, .four).orderedRanks, [.jack, .four])
        XCTAssertEqual(hand(.king, .king, .ace, .ace).orderedRanks, [.ace, .king])
        XCTAssertEqual(hand(.queen, .queen, .ace, .king).orderedRanks, [.queen, .ace, .king])
        XCTAssertEqual(hand(.nine, .ace, .king, .ten).orderedRanks, [.ace, .king, .ten, .nine])
    }

    // MARK: - The hierarchy

    func testHierarchyOrdersTheTypes() {
        let quads = hand(.two, .two, .two, .two)
        let trips = hand(.ace, .ace, .ace, .king)
        let twoPairs = hand(.ace, .ace, .king, .king)
        let pair = hand(.ace, .ace, .king, .queen)
        let noMatch = hand(.ace, .king, .queen, .jack)

        assertBeats(quads, trips, "four of a kind beats three of a kind")
        assertBeats(trips, twoPairs, "three of a kind beats two pairs")
        assertBeats(twoPairs, pair, "two pairs beats one pair")
        assertBeats(pair, noMatch, "one pair beats no matching cards")
    }

    /// The point of a strict hierarchy: the weakest pair in the deck still
    /// beats the strongest rainbow, so ranks can never override the type.
    func testRanksNeverOverrideTheType() {
        assertBeats(hand(.two, .two, .four, .three), hand(.ace, .king, .queen, .jack))
        assertBeats(hand(.two, .two, .two, .three), hand(.ace, .ace, .king, .king))
        assertBeats(hand(.two, .two, .two, .two), hand(.ace, .ace, .ace, .king))
    }

    // MARK: - Within a type

    func testFourOfAKindComparesTheQuadRank() {
        assertBeats(hand(.ace, .ace, .ace, .ace), hand(.king, .king, .king, .king))
        assertBeats(hand(.king, .king, .king, .king), hand(.queen, .queen, .queen, .queen))
    }

    func testThreeOfAKindComparesTheTripRank() {
        assertBeats(hand(.ace, .ace, .ace, .two), hand(.king, .king, .king, .ace))
        assertBeats(hand(.jack, .jack, .jack, .two), hand(.ten, .ten, .ten, .ace))
    }

    /// Unreachable from one deck — two players cannot hold the same trip rank
    /// — but the comparator is total, so it is defined and tested.
    func testThreeOfAKindFallsThroughToTheKicker() {
        assertBeats(hand(.ace, .ace, .ace, .three), hand(.ace, .ace, .ace, .two))
        XCTAssertTrue(HandComparator.isTie(hand(.ace, .ace, .ace, .three), hand(.ace, .ace, .ace, .three)))
    }

    func testTwoPairsComparesHigherPairThenLower() {
        assertBeats(hand(.ace, .ace, .king, .king), hand(.ace, .ace, .queen, .queen))
        assertBeats(hand(.king, .king, .queen, .queen), hand(.jack, .jack, .ten, .ten))
        assertBeats(hand(.ace, .ace, .two, .two), hand(.king, .king, .queen, .queen))
    }

    func testOnePairComparesPairThenBothKickers() {
        assertBeats(hand(.queen, .queen, .ace, .king), hand(.jack, .jack, .ace, .king))
        assertBeats(hand(.king, .king, .two, .three), hand(.queen, .queen, .ace, .jack))
        // QQAK beats QQA9: pair equal, high kicker equal, K > 9.
        assertBeats(hand(.queen, .queen, .ace, .king), hand(.queen, .queen, .ace, .nine))
        // QQA10 beats QQJ10: pair equal, A > J, decided before the tens.
        assertBeats(hand(.queen, .queen, .ace, .ten), hand(.queen, .queen, .jack, .ten))
    }

    func testNoMatchComparesLexicographically() {
        // A K 9 10 beats K J 8 7 on the first card.
        assertBeats(hand(.ace, .king, .nine, .ten), hand(.king, .jack, .eight, .seven))
        // A K 9 7 beats A Q J 10 on the second.
        assertBeats(hand(.ace, .king, .nine, .seven), hand(.ace, .queen, .jack, .ten))
        // Decided on the last card.
        assertBeats(hand(.ace, .king, .queen, .jack), hand(.ace, .king, .queen, .ten))
    }

    func testOrderHeldInDoesNotMatter() {
        XCTAssertTrue(HandComparator.isTie(
            hand(.nine, .ace, .ten, .king),
            hand(.ace, .king, .ten, .nine)
        ))
    }

    // MARK: - True ties

    func testIdenticalRanksTie() {
        let left = Hand(cards: [Card(.ace, .spades), Card(.king, .hearts), Card(.nine, .clubs), Card(.seven, .diamonds)])
        let right = Hand(cards: [Card(.ace, .clubs), Card(.king, .diamonds), Card(.nine, .spades), Card(.seven, .hearts)])
        XCTAssertNotEqual(left, right, "different cards")
        XCTAssertTrue(HandComparator.isTie(left, right), "same ranks must tie — suits cannot break it")
    }

    func testTwoPairsCanTieOutright() {
        let left = Hand(cards: [Card(.ace, .spades), Card(.ace, .hearts), Card(.king, .spades), Card(.king, .hearts)])
        let right = Hand(cards: [Card(.ace, .clubs), Card(.ace, .diamonds), Card(.king, .clubs), Card(.king, .diamonds)])
        XCTAssertTrue(HandComparator.isTie(left, right))
    }

    func testStrongestReturnsEveryTiedHandInOrderGiven() {
        let contenders: [(id: PlayerID, hand: Hand)] = [
            ("a", hand(.ace, .king, .nine, .seven)),
            ("b", hand(.two, .three, .four, .five)),
            ("c", hand(.ace, .king, .nine, .seven)),
        ]
        XCTAssertEqual(HandComparator.strongest(among: contenders), ["a", "c"])
    }

    func testStrongestPicksTheOneWinnerWhenThereIsNoTie() {
        let contenders: [(id: PlayerID, hand: Hand)] = [
            ("a", hand(.ace, .king, .nine, .seven)),
            ("b", hand(.two, .two, .four, .five)),
        ]
        XCTAssertEqual(HandComparator.strongest(among: contenders), ["b"])
    }

    /// No numeric score survives. A hand is its combination plus its ranks,
    /// and that is all the comparator reads.
    func testHandHasNoScore() {
        let ranking = hand(.ace, .ace, .ace, .ace).ranking
        XCTAssertEqual(ranking.combination, .fourOfAKind)
        XCTAssertEqual(ranking.orderedRanks, [.ace])
    }
}
