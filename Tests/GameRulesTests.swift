import XCTest
@testable import CardGame

final class GameRulesTests: XCTestCase {

    func testFirstBettorStartsAtTheMinimumIncrement() {
        let options = GameRules.betRange(coins: 500, highestBet: 0).options()
        XCTAssertEqual(options, [100, 200, 300, 400, 500])
    }

    func testLaterBettorsMustRaise() {
        let options = GameRules.betRange(coins: 800, highestBet: 500).options()
        XCTAssertEqual(options, [600, 700, 800])
    }

    func testBetsNeverExceedTheStack() {
        XCTAssertEqual(GameRules.betRange(coins: 300, highestBet: 100).options().last, 300)
    }

    func testNoOptionsWhenTooPoorToEvenOpen() {
        XCTAssertEqual(GameRules.betRange(coins: 0, highestBet: 0).options(), [])
        XCTAssertEqual(GameRules.betRange(coins: 50, highestBet: 0).options(), [])
    }

    /// Carried over from the original: a player who cannot cover the standing
    /// bet may still enter from the minimum rather than be shut out.
    func testShortStackMayEnterBelowTheTopBet() {
        let options = GameRules.betRange(coins: 300, highestBet: 1000).options()
        XCTAssertEqual(options, [100, 200, 300])
    }

    func testOffersAreCappedByTheTopBetAndTheStack() {
        XCTAssertEqual(GameRules.offerRange(coins: 5000, topBet: 300).options(), [100, 200, 300])
        XCTAssertEqual(GameRules.offerRange(coins: 200, topBet: 1000).options(), [100, 200])
        XCTAssertEqual(GameRules.offerRange(coins: 50, topBet: 1000).options(), [])
    }

    func testTurnOrderRotatesOneSeatPerRound() {
        XCTAssertEqual(GameRules.turnOrder(round: 0), [.south, .east, .north, .west])
        XCTAssertEqual(GameRules.turnOrder(round: 1), [.east, .north, .west, .south])
        XCTAssertEqual(GameRules.turnOrder(round: 2), [.north, .west, .south, .east])
        XCTAssertEqual(GameRules.turnOrder(round: 3), [.west, .south, .east, .north])
        XCTAssertEqual(GameRules.turnOrder(round: 4), GameRules.turnOrder(round: 0))
    }

    func testEverySeatLeadsOnceEveryFourRounds() {
        let leaders = (0..<4).map { GameRules.turnOrder(round: $0)[0] }
        XCTAssertEqual(Set(leaders).count, 4)
    }
}

final class DeckTests: XCTestCase {

    func testDeckHoldsEveryRankInEverySuit() {
        XCTAssertEqual(Deck.all.count, 16)
        XCTAssertEqual(Set(Deck.all).count, 16)
    }

    func testDealingRemovesFromTheTop() {
        var deck = Deck()
        let hand = deck.deal(4)
        XCTAssertEqual(hand.count, 4)
        XCTAssertEqual(deck.cards.count, 12)
        XCTAssertTrue(hand.allSatisfy { !deck.cards.contains($0) })
    }

    func testTheDeckDealsOutExactlyFourHands() {
        var deck = Deck()
        let hands = (0..<4).map { _ in deck.deal(4) }
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertEqual(Set(hands.flatMap { $0 }).count, 16)
    }

    func testSameSeedShufflesTheSameWay() {
        var a = RandomGenerator(seed: 42)
        var b = RandomGenerator(seed: 42)
        var deckA = Deck(), deckB = Deck()
        deckA.shuffle(using: &a)
        deckB.shuffle(using: &b)
        XCTAssertEqual(deckA.cards, deckB.cards)
    }

    func testDifferentSeedsShuffleDifferently() {
        var a = RandomGenerator(seed: 1)
        var b = RandomGenerator(seed: 2)
        var deckA = Deck(), deckB = Deck()
        deckA.shuffle(using: &a)
        deckB.shuffle(using: &b)
        XCTAssertNotEqual(deckA.cards, deckB.cards)
    }

    func testAssetNamesMatchTheCatalog() {
        XCTAssertEqual(Card(.ace, .spades).imageName, "ace_spades")
        XCTAssertEqual(Card(.jack, .diamonds).imageName, "jack_diamonds")
    }
}

final class StakeRangeTests: XCTestCase {

    func testEmptyRangeHoldsNothing() {
        XCTAssertTrue(StakeRange.empty.isEmpty)
        XCTAssertEqual(StakeRange.empty.count, 0)
        XCTAssertFalse(StakeRange.empty.contains(100))
        XCTAssertEqual(StakeRange.empty.options(), [])
    }

    func testContainsOnlyMultiplesOfTheIncrementInBounds() {
        let range = StakeRange(minimum: 600, maximum: 1000)
        XCTAssertTrue(range.contains(600))
        XCTAssertTrue(range.contains(800))
        XCTAssertTrue(range.contains(1000))
        XCTAssertFalse(range.contains(500), "below the minimum")
        XCTAssertFalse(range.contains(1100), "above the maximum")
        XCTAssertFalse(range.contains(650), "not on the increment")
    }

    func testCountAndIndexing() {
        let range = StakeRange(minimum: 100, maximum: 500)
        XCTAssertEqual(range.count, 5)
        XCTAssertEqual(range.stake(at: 0), 100)
        XCTAssertEqual(range.stake(at: 4), 500)
        XCTAssertNil(range.stake(at: 5))
        XCTAssertNil(range.stake(at: -1))
    }

    func testLargestStakeRoundsDownToTheIncrement() {
        let range = StakeRange(minimum: 100, maximum: 1000)
        XCTAssertEqual(range.largestStake(upTo: 650), 600)
        XCTAssertEqual(range.largestStake(upTo: 100), 100)
        XCTAssertEqual(range.largestStake(upTo: 99_999), 1000, "capped at the maximum")
        XCTAssertEqual(range.largestStake(upTo: 0), 100, "falls back to the minimum")
    }

    func testStakeByFractionSpansTheRange() {
        let range = StakeRange(minimum: 100, maximum: 500)
        XCTAssertEqual(range.stake(atFraction: 0), 100)
        XCTAssertEqual(range.stake(atFraction: 1), 500)
        XCTAssertEqual(range.stake(atFraction: 0.5), 300)
        XCTAssertEqual(range.stake(atFraction: -5), 100, "clamped")
        XCTAssertEqual(range.stake(atFraction: 5), 500, "clamped")
    }

    /// The whole point of the range: a huge stack must not allocate a huge
    /// array, and checking one bet must not depend on the stack's size.
    func testAHugeStackCostsNothingToValidate() {
        let range = GameRules.betRange(coins: Int.max / 2, highestBet: 0)
        XCTAssertFalse(range.isEmpty)
        XCTAssertTrue(range.contains(100))
        XCTAssertTrue(range.contains(1_000_000))
        XCTAssertFalse(range.contains(150))
        XCTAssertEqual(range.options().count, 1000, "the picker list stays capped")
    }

    func testRangesNeverExceedTheStack() {
        for coins in stride(from: 0, through: 2000, by: 50) {
            let range = GameRules.betRange(coins: coins, highestBet: 0)
            XCTAssertLessThanOrEqual(range.maximum, coins, "a player cannot bet \(range.maximum) of \(coins)")
            for stake in range.options() {
                XCTAssertEqual(stake % GameRules.betIncrement, 0)
            }
        }
    }
}
