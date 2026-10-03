import XCTest
@testable import CardGame

/// The rules SPEC.md leaves open are configuration, not decisions the engine
/// has taken. These tests pin both readings of each one, so neither is
/// authoritative by accident.
final class PolicyTests: XCTestCase {

    func testTheDefaultsAreTheOnesDocumented() {
        let policy = GamePolicy.standard
        XCTAssertEqual(policy.sharahFunding, .availableBalanceOnly)
        XCTAssertEqual(policy.elimination, .anyZeroBalanceAtRoundEnd)
        XCTAssertEqual(policy.targetTieBreak, .largerBalance)
        XCTAssertFalse(policy.sharah.onlyTopBettorMayBeOffered)
        XCTAssertFalse(policy.sharah.onlyTopBettorMayOffer)
        XCTAssertNil(policy.sharah.maxPendingOffersPerSender)
    }

    // MARK: - Where a Sharah payment comes from

    private func negotiating(funding: SharahFunding) throws -> GameEngine {
        var engine = GameEngine(
            players: table(2, balance: 4_000),
            policy: GamePolicy(sharahFunding: funding),
            seed: 71
        )
        try engine.startBetting()
        try engine.runBetting([.allIn, .allIn])
        return engine
    }

    func testAvailableBalanceOnlyLeavesAnAllInPlayerNothingToOfferWith() throws {
        var engine = try negotiating(funding: .availableBalanceOnly)
        let (payer, taker) = (engine.turnOrder[0], engine.turnOrder[1])
        XCTAssertEqual(engine.availableBalance(of: payer), 0)
        XCTAssertThrowsError(try engine.offerSharah(500, from: payer, to: taker)) {
            XCTAssertEqual($0 as? GameError, .cannotAffordSharah)
        }
    }

    func testEntireBalanceLetsAnAllInPlayerPayFromTheirBet() throws {
        var engine = try negotiating(funding: .entireBalance)
        let (payer, taker) = (engine.turnOrder[0], engine.turnOrder[1])
        XCTAssertEqual(engine.availableBalance(of: payer), 4_000)

        let id = try engine.offerSharah(500, from: payer, to: taker)
        try engine.respondToSharah(id, accept: true, by: taker)
        XCTAssertEqual(engine.players[payer]?.balance, 3_500)

        // The consequence of that reading: the payer still owes a 4,000 bet,
        // so losing it finishes the round below zero.
        let result = try engine.endRound()
        if result.loss(for: payer) > 0 {
            XCTAssertEqual(engine.players[payer]?.balance, -500)
        }
    }

    // MARK: - When a player is out

    func testEliminationCanBeLimitedToLostBets() throws {
        var players = table(2)
        players[0].balance = 0

        XCTAssertEqual(
            Settlement.eliminated(among: players, lostABet: [], rule: .anyZeroBalanceAtRoundEnd),
            [players[0].id]
        )
        XCTAssertTrue(
            Settlement.eliminated(among: players, lostABet: [], rule: .onlyWhenABetIsLost).isEmpty,
            "this reading keeps a player who reached zero some other way"
        )
        XCTAssertEqual(
            Settlement.eliminated(among: players, lostABet: [players[0].id], rule: .onlyWhenABetIsLost),
            [players[0].id]
        )
    }

    // MARK: - Two players crossing the target at once

    func testTargetTieBreakIsAChoice() {
        var players = table(2)
        players[0].balance = GameRules.targetBalance
        players[1].balance = GameRules.targetBalance + 500
        let order = players.map(\.id)

        XCTAssertEqual(
            Settlement.gameWinner(among: players, turnOrder: order, tieBreak: .largerBalance),
            players[1].id
        )
        XCTAssertEqual(
            Settlement.gameWinner(among: players, turnOrder: order, tieBreak: .firstInTurnOrder),
            players[0].id
        )
    }

    func testAnExactDrawFallsBackToTurnOrderEitherWay() {
        var players = table(2)
        players[0].balance = GameRules.targetBalance
        players[1].balance = GameRules.targetBalance
        let order = [players[1].id, players[0].id]

        for tieBreak in TargetTieBreak.allCases {
            XCTAssertEqual(
                Settlement.gameWinner(among: players, turnOrder: order, tieBreak: tieBreak),
                players[1].id,
                "\(tieBreak) should follow turn order on an exact draw"
            )
        }
    }
}
