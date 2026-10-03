import XCTest
@testable import CardGame

/// Money and betting (SPEC.md §8, §9).
///
/// The rule under test: 500 is the **increment**, not a step limit. A player
/// may bet any affordable multiple of 500 at or above what is required to stay
/// in. Nothing caps an ordinary bet by the number of players or by what the
/// previous player bet.
final class BettingTests: XCTestCase {

    func testStartingMoneyAndLimits() {
        XCTAssertEqual(GameRules.startingBalance, 5_000)
        XCTAssertEqual(GameRules.minimumBet, 500)
        XCTAssertEqual(GameRules.betUnit, 500)
        XCTAssertEqual(GameRules.targetBalance, 100_000)
        XCTAssertEqual(Player(id: "x", name: "x", seat: Seat(0)).balance, 5_000)
    }

    // MARK: - Valid and invalid amounts

    func testTheListedValidAmountsAreLegal() {
        let balance = 40_000
        for amount in [500, 1_000, 1_500, 2_000, 2_500, 3_000, 5_000, 10_000, 20_000, 40_000] {
            XCTAssertTrue(
                BettingRules.isLegal(amount: amount, standingBet: 0, balance: balance),
                "\(amount) should be a legal opening bet"
            )
        }
    }

    func testTheListedInvalidAmountsAreRejected() {
        for amount in [0, 100, 499, 1_100, 1_750, 2_300, 9_999, 10_001] {
            XCTAssertFalse(BettingRules.isWellFormed(amount), "\(amount) is not a whole 500")
            XCTAssertFalse(
                BettingRules.isLegal(amount: amount, standingBet: 0, balance: 40_000),
                "\(amount) should be rejected"
            )
        }
    }

    func testFiveHundredIsTheSmallestBet() {
        XCTAssertEqual(BettingRules.required(standingBet: 0), 500)
        XCTAssertEqual(BettingRules.range(standingBet: 0, balance: 5_000).minimum, 500)
        XCTAssertTrue(BettingRules.isLegal(amount: 500, standingBet: 0, balance: 500))
        XCTAssertFalse(BettingRules.isLegal(amount: 500, standingBet: 1_000, balance: 5_000))
    }

    /// The headline case: 10,000 is an ordinary bet for anyone who can afford
    /// it, with no all-in and no raise ladder involved.
    func testTenThousandIsAnOrdinaryBetWhenAffordable() {
        XCTAssertTrue(BettingRules.isLegal(amount: 10_000, standingBet: 0, balance: 12_000))
        XCTAssertTrue(BettingRules.isLegal(amount: 10_000, standingBet: 0, balance: 20_000))
        XCTAssertTrue(BettingRules.isLegal(amount: 10_000, standingBet: 2_000, balance: 10_000))
        XCTAssertFalse(BettingRules.isLegal(amount: 10_000, standingBet: 0, balance: 9_500))
        XCTAssertFalse(
            BettingRules.isAllIn(amount: 10_000, balance: 12_000),
            "a 10,000 bet from 12,000 is not an all-in"
        )
    }

    func testTwelveThousandCanBetTenThousandAndKeepTwoThousand() throws {
        var engine = GameEngine(players: table(balances: [12_000, 12_000]), seed: 61)
        try engine.startBetting()
        let better = engine.turnOrder[0]

        try engine.act(.bet(10_000), by: better)
        XCTAssertEqual(engine.bet(of: better), 10_000)
        XCTAssertEqual(engine.players[better]?.balance, 12_000, "balances move at settlement, not on the bet")
        XCTAssertEqual(engine.availableBalance(of: better), 2_000, "2,000 is not on the round")
        XCTAssertEqual(engine.highestBet, 10_000)
    }

    func testTwentyThousandCanBetTenThousandAndKeepTenThousand() throws {
        var engine = GameEngine(players: table(balances: [20_000, 20_000]), seed: 62)
        try engine.startBetting()
        let better = engine.turnOrder[0]

        try engine.act(.bet(10_000), by: better)
        XCTAssertEqual(engine.bet(of: better), 10_000)
        XCTAssertEqual(engine.availableBalance(of: better), 10_000)
    }

    /// There is no ceiling derived from the table size. Four players can reach
    /// far past the 3,500 that a +500/+1,000 raise ladder would have allowed.
    func testNoCeilingFromTheNumberOfPlayers() throws {
        var engine = GameEngine(players: table(4, balance: 50_000), seed: 63)
        try engine.startBetting()
        try engine.runBetting([.bet(10_000), .bet(25_000), .bet(30_000), .fold])

        XCTAssertEqual(engine.turnOrder.map { engine.bet(of: $0) }, [10_000, 25_000, 30_000, 0])
        XCTAssertEqual(engine.highestBet, 30_000)
        XCTAssertGreaterThan(engine.highestBet, 3_500, "the old ceiling is gone")
    }

    func testAnyMultipleOfFiveHundredAboveTheStandingBetIsLegal() {
        let span = BettingRules.range(standingBet: 2_000, balance: 10_000)
        XCTAssertEqual(span.minimum, 2_000)
        XCTAssertEqual(span.maximum, 10_000)
        XCTAssertEqual(span.increment, 500)
        XCTAssertEqual(span.count, 17)
        for amount in [2_000, 2_500, 3_000, 5_500, 7_000, 10_000] {
            XCTAssertTrue(span.contains(amount), "\(amount) should be in the range")
        }
        for amount in [1_500, 2_300, 10_500] {
            XCTAssertFalse(span.contains(amount), "\(amount) should not be in the range")
        }
    }

    func testARangeSkipsNothingAndAllocatesNothingLarge() {
        let span = BettingRules.range(standingBet: 0, balance: 1_000_000)
        XCTAssertEqual(span.count, 2_000)
        XCTAssertEqual(span.options(limit: 5), [500, 1_000, 1_500, 2_000, 2_500])
        XCTAssertEqual(span.largest(upTo: 7_700), 7_500)
        XCTAssertEqual(span.amount(atFraction: 1), 1_000_000)
    }

    // MARK: - All-in

    func testAllInIsStillAvailableAndMayBeBelowTheStandingBet() {
        XCTAssertEqual(BettingRules.cost(of: .allIn, standingBet: 5_000, balance: 3_000), 3_000)
        XCTAssertFalse(BettingRules.canStayIn(standingBet: 5_000, balance: 3_000))
        XCTAssertTrue(BettingRules.isLegal(amount: 3_000, standingBet: 5_000, balance: 3_000))
        XCTAssertTrue(BettingRules.range(standingBet: 5_000, balance: 3_000).isEmpty)
    }

    /// An all-in is the one amount exempt from the 500 rule, because a balance
    /// need not be a multiple of 500 — a tie remainder can leave an odd one.
    func testAllInIsExemptFromTheIncrementRule() {
        XCTAssertFalse(BettingRules.isWellFormed(3_334))
        XCTAssertTrue(BettingRules.isLegal(amount: 3_334, standingBet: 5_000, balance: 3_334))
        XCTAssertTrue(BettingRules.isLegal(amount: 3_334, standingBet: 0, balance: 3_334))
    }

    /// And an odd standing bet left by an all-in rounds the next player's
    /// minimum up to a whole 500.
    func testAnOddStandingBetRoundsTheMinimumUp() {
        let span = BettingRules.range(standingBet: 3_334, balance: 10_000)
        XCTAssertEqual(span.minimum, 3_500)
        XCTAssertFalse(span.contains(3_334))
    }

    func testAllInWorksThroughTheEngine() throws {
        var engine = GameEngine(players: table(balances: [50_000, 50_000, 3_000]), seed: 64)
        try engine.startBetting()
        try engine.runBetting([.bet(10_000), .bet(20_000), .allIn])
        let order = engine.turnOrder

        XCTAssertEqual(order.map { engine.bet(of: $0) }, [10_000, 20_000, 3_000])
        XCTAssertEqual(engine.highestBet, 20_000, "an all-in below the top does not become the top")
        XCTAssertEqual(engine.topBettor, order[1])
        XCTAssertEqual(engine.standing(of: order[2]), .committed, "a short stack is still in the round")
    }

    func testFoldIsAlwaysAvailableAndCostsNothing() {
        XCTAssertEqual(BettingRules.cost(of: .fold, standingBet: 50_000, balance: 0), 0)
        XCTAssertNil(BettingRules.cost(of: .allIn, standingBet: 50_000, balance: 0))
        XCTAssertFalse(BettingRules.canStayIn(standingBet: 50_000, balance: 0))
    }

    // MARK: - Through the engine

    func testEngineRejectsAnIllegalAmount() throws {
        var engine = GameEngine(players: table(3), seed: 11)
        try engine.startBetting()
        let first = engine.turnOrder[0]
        XCTAssertThrowsError(try engine.act(.bet(1_100), by: first)) {
            XCTAssertEqual($0 as? GameError, .illegalAction(.bet(1_100)))
        }
        XCTAssertThrowsError(try engine.bet(1_750, by: first)) {
            XCTAssertEqual($0 as? GameError, .illegalBet(1_750))
        }
        XCTAssertThrowsError(try engine.bet(2_300, by: first)) {
            XCTAssertEqual($0 as? GameError, .illegalBet(2_300))
        }
        try engine.bet(2_500, by: first)
        XCTAssertEqual(engine.bet(of: first), 2_500)
    }

    func testEngineRejectsABetItCannotAfford() throws {
        var engine = GameEngine(players: table(2, balance: 3_000), seed: 12)
        try engine.startBetting()
        XCTAssertThrowsError(try engine.bet(3_500, by: engine.turnOrder[0])) {
            XCTAssertEqual($0 as? GameError, .illegalBet(3_500))
        }
    }

    func testEngineRejectsABetBelowTheStandingBet() throws {
        var engine = GameEngine(players: table(3, balance: 20_000), seed: 13)
        try engine.startBetting()
        try engine.bet(5_000, by: engine.turnOrder[0])
        XCTAssertThrowsError(try engine.bet(2_000, by: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .illegalBet(2_000))
        }
        XCTAssertNoThrow(try engine.bet(5_000, by: engine.turnOrder[1]))
    }

    func testEngineTracksTheHighestBetAndItsOwner() throws {
        var engine = GameEngine(players: table(3, balance: 30_000), seed: 3)
        try engine.startBetting()
        let order = engine.turnOrder
        try engine.bet(500, by: order[0])
        try engine.bet(4_000, by: order[1])
        try engine.bet(12_000, by: order[2])
        XCTAssertEqual(engine.highestBet, 12_000)
        XCTAssertEqual(engine.topBettor, order[2])
    }

    func testFoldingCommitsNothing() throws {
        var engine = GameEngine(players: table(3), seed: 8)
        try engine.startBetting()
        let order = engine.turnOrder
        try engine.bet(1_000, by: order[0])
        try engine.fold(order[1])
        XCTAssertEqual(engine.bet(of: order[1]), 0)
        XCTAssertEqual(engine.standing(of: order[1]), .folded)
        XCTAssertEqual(engine.highestBet, 1_000, "a fold cannot change the highest bet")
    }

    /// Betting is a single pass: once the last player has acted the round moves
    /// on, which is why players reach a showdown holding unequal bets.
    func testBettingIsOneLapOfTheTable() throws {
        var engine = GameEngine(players: table(4, balance: 20_000), seed: 2)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .bet(1_000), .bet(6_000), .fold])
        XCTAssertEqual(engine.phase, .negotiation)
        XCTAssertEqual(engine.turnOrder.map { engine.bet(of: $0) }, [500, 1_000, 6_000, 0])
    }

    func testOutOfTurnActionsAreRejected() throws {
        var engine = GameEngine(players: table(3), seed: 1)
        try engine.startBetting()
        XCTAssertThrowsError(try engine.bet(500, by: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .notYourTurn)
        }
    }

    func testThePickerIsOfferedOnlyLegalAmounts() throws {
        var engine = GameEngine(players: table(2, balance: 12_000), seed: 14)
        try engine.startBetting()
        let player = engine.turnOrder[0]
        let offered = engine.legalBetAmounts(for: player, limit: 1_000)

        XCTAssertEqual(offered.first, 500)
        XCTAssertEqual(offered.last, 12_000)
        XCTAssertTrue(offered.contains(10_000))
        for amount in offered {
            XCTAssertTrue(engine.isLegal(.bet(amount), for: player), "\(amount) was offered but is illegal")
        }
    }
}
