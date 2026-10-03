import XCTest
@testable import CardGame

/// Settlement (SPEC.md §7). There is no pot: the winner's reward and each
/// loser's loss are independent numbers.
final class SettlementTests: XCTestCase {

    /// The worked example from SPEC.md §7 — A 3,000, B 1,000, C 4,000,
    /// D 10,000, and A wins.
    func testWinnerTakesTheHighestBetAndLosersPayTheirOwn() {
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", hand(.ace, .ace, .ace, .ace)),
            ("B", hand(.two, .three, .four, .five)),
            ("C", hand(.king, .king, .queen, .queen)),
            ("D", hand(.jack, .jack, .nine, .eight)),
        ]
        let bets: [PlayerID: Int] = ["A": 3_000, "B": 1_000, "C": 4_000, "D": 10_000]
        let ledger = Settlement.settle(showdown: showdown, bets: bets)

        XCTAssertEqual(ledger.winners, ["A"])
        XCTAssertEqual(ledger.highestBet, 10_000)
        XCTAssertEqual(ledger.netChange["A"], 10_000, "the winner collects the highest bet, not their own")
        XCTAssertEqual(ledger.netChange["B"], -1_000)
        XCTAssertEqual(ledger.netChange["C"], -4_000)
        XCTAssertEqual(ledger.netChange["D"], -10_000)
    }

    func testWinnerCanCollectMoreThanTheyBet() {
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", hand(.ace, .ace, .ace, .ace)),
            ("B", hand(.two, .three, .four, .five)),
        ]
        let ledger = Settlement.settle(showdown: showdown, bets: ["A": 500, "B": 20_000])
        XCTAssertEqual(ledger.rewards["A"], 20_000)
        XCTAssertEqual(ledger.losses["B"], 20_000)
    }

    /// Explicitly not a pot: the losers' bets are not summed and handed over.
    func testLosersBetsAreNotPooled() {
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", hand(.ace, .ace, .ace, .ace)),
            ("B", hand(.two, .three, .four, .five)),
            ("C", hand(.two, .three, .four, .six)),
            ("D", hand(.two, .three, .four, .seven)),
        ]
        let bets: [PlayerID: Int] = ["A": 3_000, "B": 1_000, "C": 4_000, "D": 10_000]
        let ledger = Settlement.settle(showdown: showdown, bets: bets)

        let paid = ledger.losses.values.reduce(0, +)
        let collected = ledger.rewards.values.reduce(0, +)
        XCTAssertEqual(paid, 15_000)
        XCTAssertEqual(collected, 10_000)
        XCTAssertNotEqual(paid, collected, "a pot would make these equal")
    }

    /// The flip side of the same rule, recorded in SPEC.md §9: heads-up, a big
    /// winner is paid more than the loser pays.
    func testMoneySupplyIsNotConserved() {
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", hand(.ace, .ace, .ace, .ace)),
            ("B", hand(.two, .three, .four, .five)),
        ]
        let ledger = Settlement.settle(showdown: showdown, bets: ["A": 10_000, "B": 100])
        XCTAssertEqual(ledger.netChange["A"], 10_000)
        XCTAssertEqual(ledger.netChange["B"], -100)
        XCTAssertEqual(ledger.netChange.values.reduce(0, +), 9_900, "created, as the rule specifies")
    }

    // MARK: - Ties

    func testTwoWayTieSplitsTheHighestBet() {
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", hand(.ace, .king, .nine, .seven)),
            ("B", hand(.ace, .king, .nine, .seven)),
            ("C", hand(.two, .three, .four, .five)),
        ]
        let ledger = Settlement.settle(showdown: showdown, bets: ["A": 500, "B": 500, "C": 10_000])
        XCTAssertEqual(ledger.winners, ["A", "B"])
        XCTAssertEqual(ledger.rewards["A"], 5_000)
        XCTAssertEqual(ledger.rewards["B"], 5_000)
        XCTAssertEqual(ledger.losses["C"], 10_000)
    }

    /// 10,000 over three winners is 3,333 each with 1 left over, and the
    /// remainder goes to whoever comes first in turn order.
    func testThreeWayTieGivesTheRemainderToTheFirstInTurnOrder() {
        let tied = hand(.ace, .king, .nine, .seven)
        let showdown: [(id: PlayerID, hand: Hand)] = [
            ("A", tied), ("B", tied), ("C", tied),
            ("D", hand(.two, .three, .four, .five)),
        ]
        let ledger = Settlement.settle(showdown: showdown, bets: ["A": 500, "B": 500, "C": 500, "D": 10_000])
        XCTAssertEqual(ledger.winners, ["A", "B", "C"])
        XCTAssertEqual(ledger.rewards["A"], 3_334)
        XCTAssertEqual(ledger.rewards["B"], 3_333)
        XCTAssertEqual(ledger.rewards["C"], 3_333)
        XCTAssertEqual(ledger.rewards.values.reduce(0, +), 10_000, "the split loses nothing")
    }

    func testTheRemainderFollowsTurnOrderNotPlayerName() {
        let tied = hand(.ace, .king, .nine, .seven)
        let showdown: [(id: PlayerID, hand: Hand)] = [("C", tied), ("A", tied), ("B", tied)]
        let ledger = Settlement.settle(showdown: showdown, bets: ["C": 1_000, "A": 1_000, "B": 1_000])
        XCTAssertEqual(ledger.winners, ["C", "A", "B"])
        XCTAssertEqual(ledger.rewards["C"], 334)
        XCTAssertEqual(ledger.rewards["A"], 333)
        XCTAssertEqual(ledger.rewards["B"], 333)
    }

    /// Four is the largest tie one deck allows: four players can hold the same
    /// four distinct ranks, one suit each.
    func testFourWayTieSplitsEvenly() {
        let ranks: [Rank] = [.ace, .king, .nine, .seven]
        let hands = Suit.allCases.map { suit in Hand(cards: ranks.map { Card($0, suit) }) }
        let ids: [PlayerID] = ["A", "B", "C", "D"]
        let showdown = Array(zip(ids, hands)).map { (id: $0.0, hand: $0.1) }
        let ledger = Settlement.settle(showdown: showdown, bets: Dictionary(uniqueKeysWithValues: ids.map { ($0, 2_000) }))

        XCTAssertEqual(ledger.winners, ids)
        for id in ids { XCTAssertEqual(ledger.rewards[id], 500) }
        XCTAssertTrue(ledger.losses.isEmpty, "everyone tied, so nobody lost")
    }

    func testNobodyAtTheShowdownSettlesToNothing() {
        XCTAssertEqual(Settlement.settle(showdown: [], bets: ["A": 1_000]), .empty)
    }

    // MARK: - Elimination and the target

    func testEliminationAtZero() {
        var players = table(3)
        players[1].balance = 0
        XCTAssertEqual(Settlement.eliminated(among: players), [players[1].id])
    }

    func testAlreadyEliminatedPlayersAreNotReported() {
        var players = table(2)
        players[0].balance = 0
        players[0].isEliminated = true
        XCTAssertTrue(Settlement.eliminated(among: players).isEmpty)
    }

    func testReachingTheTargetWinsTheGame() {
        var players = table(3)
        players[2].balance = GameRules.targetBalance
        XCTAssertEqual(Settlement.gameWinner(among: players, turnOrder: players.map(\.id)), players[2].id)
    }

    func testBelowTheTargetNobodyWins() {
        var players = table(3)
        players[0].balance = GameRules.targetBalance - 1
        XCTAssertNil(Settlement.gameWinner(among: players, turnOrder: players.map(\.id)))
    }

    func testTheLargerBalanceTakesTheGameWhenTwoCrossTogether() {
        var players = table(2)
        players[0].balance = GameRules.targetBalance
        players[1].balance = GameRules.targetBalance + 500
        XCTAssertEqual(Settlement.gameWinner(among: players, turnOrder: players.map(\.id)), players[1].id)
    }
}
