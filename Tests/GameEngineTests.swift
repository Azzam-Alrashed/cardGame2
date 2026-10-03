import XCTest
@testable import CardGame

/// The round, end to end: dealing, the state machine, settlement against real
/// hands, elimination and the end of the game.
final class GameEngineTests: XCTestCase {

    // MARK: - Dealing

    func testEveryPlayerGetsFourCards() throws {
        var engine = GameEngine(players: table(7), seed: 41)
        try engine.startRound()
        for id in engine.turnOrder {
            XCTAssertEqual(engine.hand(of: id, asSeenBy: id)?.cards.count, GameRules.handSize)
        }
    }

    func testNoPhysicalCardIsDealtTwice() throws {
        var engine = GameEngine(players: table(13), seed: 42)
        try engine.startRound()
        let dealt = engine.turnOrder.flatMap { engine.hand(of: $0, asSeenBy: $0)?.cards ?? [] }
        XCTAssertEqual(dealt.count, 52)
        XCTAssertEqual(Set(dealt).count, 52, "the same card reached two players")
        XCTAssertEqual(engine.undealtCards, 0, "thirteen players use the whole deck")
    }

    func testUndealtCardsStayUnused() throws {
        var engine = GameEngine(players: table(5), seed: 43)
        try engine.startRound()
        XCTAssertEqual(engine.undealtCards, 52 - 5 * GameRules.handSize)
    }

    /// One card each, round the table, four times over — starting with the
    /// round's first player and moving to their right, which is the next seat
    /// index. The test replays the same seeded shuffle to know what to expect.
    func testDealIsOneCardAtATimeRightToLeft() throws {
        let seed: UInt64 = 77
        var engine = GameEngine(players: table(5), seed: seed)
        try engine.startRound()

        var deck = Deck()
        var rng = RandomGenerator(seed: seed)
        deck.shuffle(using: &rng)
        let shuffled = deck.cards
        let players = engine.turnOrder.count

        for (position, id) in engine.turnOrder.enumerated() {
            let expected = (0..<GameRules.handSize).map { shuffled[position + $0 * players] }
            XCTAssertEqual(
                engine.hand(of: id, asSeenBy: id)?.cards,
                expected,
                "\(id) was dealt out of order"
            )
        }
    }

    func testTheDealRotatesEachRound() throws {
        var engine = GameEngine(players: table(4), seed: 44)
        try engine.startBetting()
        let first = engine.turnOrder
        try engine.runBetting([.fold, .fold, .fold, .stayIn])
        try engine.endRound()

        try engine.startBetting()
        XCTAssertEqual(engine.turnOrder.first, first[1], "the next round starts one seat along")
        XCTAssertEqual(engine.turnOrder, Array(first[1...]) + [first[0]])
    }

    func testCardsCannotChangeAfterTheDeal() throws {
        var engine = GameEngine(players: table(3), seed: 45)
        try engine.startBetting()
        let dealt = engine.turnOrder.map { engine.hand(of: $0, asSeenBy: $0) }
        try engine.runBetting([.stayIn, .stayIn, .stayIn])
        try engine.endRound()
        let revealed = engine.turnOrder.map { id in engine.hand(of: id, asSeenBy: id) }
        XCTAssertEqual(dealt, revealed)
    }

    // MARK: - The state machine

    func testPhasesFollowTheSpecifiedSequence() throws {
        var engine = GameEngine(players: table(2), seed: 46)
        XCTAssertEqual(engine.phase, .waitingForPlayers)
        try engine.startRound()
        XCTAssertEqual(engine.phase, .dealing)
        try engine.finishDealing()
        XCTAssertEqual(engine.phase, .privateHands)
        try engine.beginBetting()
        XCTAssertEqual(engine.phase.name, "BETTING")
        try engine.runBetting([.stayIn, .stayIn])
        XCTAssertEqual(engine.phase, .negotiation)
        try engine.closeNegotiation()
        XCTAssertEqual(engine.phase, .showdown)
        try engine.settle()
        XCTAssertEqual(engine.phase, .settlement)
        try engine.checkGameEnd()
        XCTAssertEqual(engine.phase, .roundOver)
    }

    func testActionsOutOfTheirStateAreRejected() throws {
        var engine = GameEngine(players: table(2), seed: 47)
        XCTAssertThrowsError(try engine.beginBetting()) { XCTAssertEqual($0 as? GameError, .wrongPhase) }

        try engine.startRound()
        XCTAssertThrowsError(try engine.startRound()) { XCTAssertEqual($0 as? GameError, .wrongPhase) }
        XCTAssertThrowsError(try engine.beginBetting()) { XCTAssertEqual($0 as? GameError, .wrongPhase) }
        XCTAssertThrowsError(try engine.act(.bet(500), by: engine.turnOrder[0])) {
            XCTAssertEqual($0 as? GameError, .wrongPhase)
        }

        try engine.finishDealing()
        try engine.beginBetting()
        XCTAssertThrowsError(try engine.settle()) { XCTAssertEqual($0 as? GameError, .wrongPhase) }
        XCTAssertThrowsError(try engine.checkGameEnd()) { XCTAssertEqual($0 as? GameError, .wrongPhase) }

        try engine.runBetting([.stayIn, .stayIn])
        try engine.endRound()
        XCTAssertThrowsError(try engine.act(.bet(500), by: engine.turnOrder[0])) {
            XCTAssertEqual($0 as? GameError, .wrongPhase)
        }
    }

    func testARoundNeedsTwoPlayersWithMoney() throws {
        var players = table(2)
        players[1].balance = 0
        var engine = GameEngine(players: players, seed: 48)
        XCTAssertThrowsError(try engine.startRound()) {
            XCTAssertEqual($0 as? GameError, .notEnoughPlayers)
        }
    }

    // MARK: - Settlement against real hands

    /// Whoever the shuffle favours, the money has to move the way SPEC.md §7
    /// says: the winner collects the round's highest bet, every other player at
    /// the showdown pays their own bet, and nobody else pays anything.
    func testSettlementInvariantsHoldForEverySeed() throws {
        for seed in UInt64(0)..<40 {
            var engine = GameEngine(players: table(4, balance: 20_000), seed: seed)
            try engine.startBetting()
            let order = engine.turnOrder
            let before = engine.players.mapValues(\.balance)
            try engine.runBetting([.stayIn, .bet(1_000), .fold, .bet(5_000)])
            let bets = Dictionary(uniqueKeysWithValues: order.map { ($0, engine.bet(of: $0)) })
            let result = try engine.endRound()

            XCTAssertEqual(result.highestBet, bets.values.max())
            XCTAssertFalse(result.winners.isEmpty)

            for id in order {
                let change = (engine.players[id]?.balance ?? 0) - (before[id] ?? 0)
                if result.winners.contains(id) {
                    XCTAssertEqual(change, result.reward(for: id), "seed \(seed): winner's reward")
                } else if result.revealedHands[id] != nil {
                    XCTAssertEqual(change, -bets[id]!, "seed \(seed): a loser pays exactly their own bet")
                } else {
                    XCTAssertEqual(change, 0, "seed \(seed): a player who left pays nothing")
                }
            }
            XCTAssertTrue(engine.players.values.allSatisfy { $0.balance >= 0 }, "seed \(seed): negative balance")
        }
    }

    func testTheLastPlayerStandingWinsWithoutAShowdown() throws {
        var engine = GameEngine(players: table(3), seed: 49)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .fold, .fold])
        let alone = engine.turnOrder[0]

        let result = try engine.endRound()
        XCTAssertEqual(result.winners, [alone])
        XCTAssertEqual(result.reward(for: alone), 500, "their own bet is the round's highest")
        XCTAssertEqual(engine.players[alone]?.balance, GameRules.startingBalance + 500)
    }

    func testEverybodyFoldingMovesNoMoney() throws {
        var engine = GameEngine(players: table(3), seed: 50)
        try engine.startBetting()
        let before = engine.players.mapValues(\.balance)
        try engine.runBetting([.fold, .fold, .fold])

        let result = try engine.endRound()
        XCTAssertTrue(result.winners.isEmpty)
        XCTAssertEqual(engine.players.mapValues(\.balance), before)
    }

    // MARK: - Elimination and the end of the game

    /// Two all-ins, and the round's highest bet is 99,500 either way — so
    /// whoever wins crosses the target, and whoever loses is wiped out.
    func testLosingEverythingEliminatesAndCrossingTheTargetEndsTheGame() throws {
        var engine = GameEngine(players: table(balances: [99_500, 10_000]), seed: 51)
        try engine.startBetting()
        try engine.runBetting([.allIn, .allIn])

        let result = try engine.endRound()
        XCTAssertEqual(result.highestBet, 99_500)
        XCTAssertEqual(result.eliminated.count, 1, "the loser has nothing left")
        let loser = result.eliminated[0]
        XCTAssertEqual(engine.players[loser]?.balance, 0)
        XCTAssertTrue(engine.players[loser]?.isEliminated == true)

        XCTAssertNotNil(result.gameWinner)
        XCTAssertEqual(engine.phase, .gameOver(winner: result.gameWinner!))
        XCTAssertGreaterThanOrEqual(engine.players[result.gameWinner!]!.balance, GameRules.targetBalance)
    }

    func testAnEliminatedPlayerIsNotDealtIn() throws {
        var engine = GameEngine(players: table(balances: [1_000, 20_000, 20_000]), seed: 52)
        var eliminated: PlayerID?

        for _ in 0..<30 {
            guard engine.activePlayers.count >= GameRules.minPlayers else { break }
            try engine.startBetting()
            for id in engine.turnOrder {
                guard case .betting = engine.phase else { break }
                try engine.act(.allIn, by: id)
            }
            let result = try engine.endRound()
            if let first = result.eliminated.first { eliminated = first; break }
            if case .gameOver = engine.phase { break }
        }

        guard let eliminated else { return XCTFail("nobody went broke in thirty all-in rounds") }
        XCTAssertTrue(engine.players[eliminated]?.isEliminated == true)
        if engine.activePlayers.count >= GameRules.minPlayers {
            try engine.startRound()
            XCTAssertFalse(engine.turnOrder.contains(eliminated), "an eliminated player was dealt in")
            XCTAssertNil(engine.hand(of: eliminated, asSeenBy: eliminated))
        }
    }

    /// A long session driven by the AI: balances stay whole and non-negative,
    /// and the game either ends on the target or keeps a legal table.
    func testALongSessionStaysConsistent() throws {
        var engine = GameEngine(players: table(5), seed: 53)
        var ai = Dictionary(uniqueKeysWithValues: engine.roster.enumerated().map { index, player in
            (player.id, AIStrategy(personality: [.cautious, .balanced, .reckless][index % 3], seed: UInt64(index) + 1))
        })

        var rounds = 0
        while rounds < 300 {
            if case .gameOver = engine.phase { break }
            guard engine.activePlayers.count >= GameRules.minPlayers else { break }
            try engine.startBetting()

            while case .betting(let turn) = engine.phase {
                let hand = engine.hand(of: turn, asSeenBy: turn)!
                let balance = engine.players[turn]!.balance
                let action = ai[turn]!.decideBet(hand: hand, balance: balance, table: engine.publicView(for: turn))
                try engine.act(action, by: turn)
            }
            try engine.endRound()
            rounds += 1

            XCTAssertTrue(engine.players.values.allSatisfy { $0.balance >= 0 }, "round \(rounds): negative balance")
        }

        XCTAssertGreaterThan(rounds, 0)
        XCTAssertEqual(engine.roundIndex, rounds)
    }
}
