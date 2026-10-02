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

    /// The spec flags this collision explicitly: aces-and-jacks scores the
    /// same as kings-and-queens. The scores still tie — that is the scoring
    /// table — and `HandOrderingTests` covers how the round is decided.
    func testTwoPairTieFromTheSpec() {
        let acesAndJacks = hand([(.ace, .spades), (.ace, .clubs), (.jack, .hearts), (.jack, .diamonds)])
        let kingsAndQueens = hand([(.king, .spades), (.king, .clubs), (.queen, .hearts), (.queen, .diamonds)])
        XCTAssertEqual(acesAndJacks.score, 2900)
        XCTAssertEqual(kingsAndQueens.score, 2900)
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

/// The tiebreak chain: score, then grouped ranks, then loose ranks, then the
/// cards themselves with suit order ♠ > ♣ > ♥ > ♦.
final class HandOrderingTests: XCTestCase {

    private func hand(_ cards: [(Rank, Suit)]) -> Hand {
        Hand(cards: cards.map { Card($0.0, $0.1) })
    }

    func testSuitOrder() {
        XCTAssertGreaterThan(Suit.spades, Suit.clubs)
        XCTAssertGreaterThan(Suit.clubs, Suit.hearts)
        XCTAssertGreaterThan(Suit.hearts, Suit.diamonds)
        XCTAssertEqual(Suit.allCases.sorted(by: >), [.spades, .clubs, .hearts, .diamonds])
    }

    func testCardsOrderByRankThenSuit() {
        XCTAssertGreaterThan(Card(.ace, .diamonds), Card(.king, .spades), "rank outranks suit")
        XCTAssertGreaterThan(Card(.ace, .spades), Card(.ace, .clubs), "suit settles equal ranks")
    }

    /// The collision the spec called out: both hands score 2900, and the
    /// higher pair now takes it.
    func testAcesAndJacksBeatsKingsAndQueens() {
        let acesAndJacks = hand([(.ace, .spades), (.ace, .clubs), (.jack, .hearts), (.jack, .diamonds)])
        let kingsAndQueens = hand([(.king, .spades), (.king, .clubs), (.queen, .hearts), (.queen, .diamonds)])

        XCTAssertEqual(acesAndJacks.score, kingsAndQueens.score, "the scores still tie")
        XCTAssertGreaterThan(acesAndJacks, kingsAndQueens, "but the hand with aces wins")
    }

    func testSuitSettlesHandsWithTheSameRanks() {
        let spadeHigh = hand([(.ace, .spades), (.ace, .hearts), (.king, .spades), (.queen, .spades)])
        let clubHigh = hand([(.ace, .clubs), (.ace, .diamonds), (.king, .clubs), (.queen, .clubs)])

        XCTAssertEqual(spadeHigh.score, clubHigh.score)
        XCTAssertGreaterThan(spadeHigh, clubHigh, "the ace of spades carries it")
    }

    func testLooseRanksBreakTiesBeforeSuitsDo() {
        // Both are a pair of queens; the loose cards decide first.
        let withAce = hand([(.queen, .spades), (.queen, .clubs), (.ace, .diamonds), (.jack, .diamonds)])
        let withKing = hand([(.queen, .hearts), (.queen, .diamonds), (.king, .diamonds), (.jack, .spades)])
        XCTAssertGreaterThan(withAce, withKing)
    }

    func testScoreStillDecidesWheneverItDiffers() {
        // Nothing in the chain may override the scoring table: scan every
        // possible pair of hands that can be dealt from one deck.
        let deck = Deck.all
        var checked = 0
        for i in 0..<deck.count {
            for j in (i + 1)..<deck.count {
                for k in (j + 1)..<deck.count {
                    for l in (k + 1)..<deck.count {
                        let left = Hand(cards: [deck[i], deck[j], deck[k], deck[l]])
                        let remaining = deck.filter { !left.cards.contains($0) }
                        let right = Hand(cards: Array(remaining.prefix(4)))
                        if left.score != right.score {
                            XCTAssertEqual(left < right, left.score < right.score)
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testOrderingIsConsistentWithEquality() {
        let dealtOneWay = hand([(.ace, .spades), (.king, .clubs), (.queen, .hearts), (.jack, .diamonds)])
        let dealtAnother = hand([(.jack, .diamonds), (.queen, .hearts), (.ace, .spades), (.king, .clubs)])

        XCTAssertEqual(dealtOneWay, dealtAnother, "the same cards are the same hand")
        XCTAssertFalse(dealtOneWay < dealtAnother)
        XCTAssertFalse(dealtAnother < dealtOneWay)
        XCTAssertEqual(dealtOneWay.hashValue, dealtAnother.hashValue)
    }

    func testSortingIsATotalOrderOverEveryHand() {
        let deck = Deck.all
        var hands: [Hand] = []
        for i in 0..<deck.count {
            for j in (i + 1)..<deck.count {
                for k in (j + 1)..<deck.count {
                    for l in (k + 1)..<deck.count {
                        hands.append(Hand(cards: [deck[i], deck[j], deck[k], deck[l]]))
                    }
                }
            }
        }
        let sorted = hands.sorted()
        XCTAssertEqual(sorted.count, 1820)
        // Strictly increasing: adjacent hands never compare equal.
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertTrue(lower < higher, "\(lower) and \(higher) are not ordered")
        }
        XCTAssertEqual(sorted.last?.score, 4400, "four aces is still the best hand")
        XCTAssertEqual(sorted.first?.score, 100, "a rainbow is still the worst")
    }
}
