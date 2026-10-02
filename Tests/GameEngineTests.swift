import XCTest
@testable import CardGame

final class GameEngineTests: XCTestCase {

    private let a: PlayerID = "A"
    private let b: PlayerID = "B"
    private let c: PlayerID = "C"
    private let d: PlayerID = "D"

    private func makeEngine(
        seed: UInt64 = 7,
        coins: Int = GameRules.startingCoins,
        payout: GameRules.Payout = GameRules.defaultPayout
    ) -> GameEngine {
        GameEngine(players: [
            Player(id: "A", name: "Azzam", avatarName: "image6", seat: .south, coins: coins, isHuman: true),
            Player(id: "B", name: "Ahmad", avatarName: "image1", seat: .east, coins: coins),
            Player(id: "C", name: "Omar", avatarName: "image5", seat: .north, coins: coins),
            Player(id: "D", name: "Ammar", avatarName: "image2", seat: .west, coins: coins),
        ], payout: payout, seed: seed)
    }

    /// Walks betting to its end, letting `action` choose for each seat from
    /// that seat's hand and legal bets.
    private func runBetting(
        _ engine: inout GameEngine,
        action: (PlayerID, Hand, StakeRange) -> BettingDecision
    ) throws {
        while case .betting(let seat) = engine.phase {
            guard let id = engine.player(at: seat)?.id,
                  let hand = engine.participation[id]?.hand
            else { break }
            switch action(id, hand, engine.betRange(for: id)) {
            case .bet(let amount): try engine.bet(amount, from: id)
            case .withdraw: try engine.withdraw(id)
            }
        }
    }

    // MARK: - Dealing

    func testStartRoundDealsFourCardsToEachSeatWithNoOverlap() throws {
        var engine = makeEngine()
        try engine.startRound()

        XCTAssertEqual(engine.participation.count, 4)
        let allCards = engine.participation.values.flatMap(\.hand.cards)
        XCTAssertEqual(allCards.count, 16)
        XCTAssertEqual(Set(allCards).count, 16, "a card was dealt twice")
    }

    func testRoundOpensOnTheFirstSeatInTurnOrder() throws {
        var engine = makeEngine()
        try engine.startRound()
        XCTAssertEqual(engine.phase, .betting(seat: .south))
    }

    func testCannotBetBeforeTheRoundStarts() {
        var engine = makeEngine()
        XCTAssertThrowsError(try engine.bet(100, from: a)) { error in
            XCTAssertEqual(error as? GameError, .wrongPhase)
        }
    }

    // MARK: - Betting

    func testBettingWalksTheTurnOrderThenOpensNegotiation() throws {
        var engine = makeEngine()
        try engine.startRound()

        try engine.bet(100, from: a)
        XCTAssertEqual(engine.phase, .betting(seat: .east))
        try engine.bet(200, from: b)
        XCTAssertEqual(engine.phase, .betting(seat: .north))
        try engine.withdraw(c)
        XCTAssertEqual(engine.phase, .betting(seat: .west))
        try engine.bet(300, from: d)
        XCTAssertEqual(engine.phase, .negotiation)
    }

    func testPlayingOutOfTurnIsRejected() throws {
        var engine = makeEngine()
        try engine.startRound()
        XCTAssertThrowsError(try engine.bet(100, from: b)) { error in
            XCTAssertEqual(error as? GameError, .notYourTurn)
        }
    }

    func testBetMustBeALegalOption() throws {
        var engine = makeEngine()
        try engine.startRound()
        // Not a multiple of the increment.
        XCTAssertThrowsError(try engine.bet(150, from: a)) { error in
            XCTAssertEqual(error as? GameError, .illegalBet(150))
        }
        // More than the stack.
        XCTAssertThrowsError(try engine.bet(99_999, from: a)) { error in
            XCTAssertEqual(error as? GameError, .illegalBet(99_999))
        }
    }

    func testBetMustRaiseTheStandingBet() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(1000, from: a)
        XCTAssertThrowsError(try engine.bet(500, from: b)) { error in
            XCTAssertEqual(error as? GameError, .illegalBet(500))
        }
    }

    func testTopBettorTracksTheHighestBet() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        XCTAssertEqual(engine.topBettor, a)
        try engine.bet(900, from: b)
        XCTAssertEqual(engine.topBettor, b)
        XCTAssertEqual(engine.highestBet, 900)
        try engine.withdraw(c)
        try engine.withdraw(d)
        XCTAssertEqual(engine.topBettor, b, "withdrawing does not change the top bet")
    }

    func testWithdrawnPlayersAreNotEntrants() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.withdraw(b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        XCTAssertEqual(engine.entrants, [a])
    }

    func testEntrantsAreListedInTurnOrder() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(200, from: b)
        try engine.withdraw(c)
        try engine.bet(300, from: d)
        XCTAssertEqual(engine.entrants, [a, b, d])
    }

    func testARoundNobodyEntersSkipsStraightToReveal() throws {
        var engine = makeEngine()
        try engine.startRound()
        try runBetting(&engine) { _, _, _ in .withdraw }

        guard case .reveal(let outcome) = engine.phase else {
            return XCTFail("expected reveal, got \(engine.phase)")
        }
        XCTAssertNil(outcome.winner)
        XCTAssertEqual(outcome.pot, 0)
        XCTAssertTrue(outcome.coinChanges.isEmpty)
        XCTAssertTrue(engine.players.values.allSatisfy { $0.coins == GameRules.startingCoins })
    }

    // MARK: - Offers

    func testOnlyNonTopEntrantsMayOffer() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        XCTAssertFalse(engine.offerRange(for: a).isEmpty, "entrant below the top bet may offer")
        XCTAssertTrue(engine.offerRange(for: b).isEmpty, "the top bettor has nobody to offer")
        XCTAssertTrue(engine.offerRange(for: c).isEmpty, "a withdrawn player may not offer")
    }

    func testOffersAreCappedByTheTopBet() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(300, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        XCTAssertEqual(engine.offerRange(for: a).options(), [100, 200, 300])
        XCTAssertThrowsError(try engine.submitOffer(400, from: a)) { error in
            XCTAssertEqual(error as? GameError, .illegalOffer(400))
        }
    }

    func testAnOfferCannotBeSentTwiceOrRevoked() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        try engine.submitOffer(200, from: a)
        XCTAssertEqual(engine.offers.count, 1)
        XCTAssertTrue(engine.offerRange(for: a).isEmpty, "no second offer once one is in flight")
        XCTAssertThrowsError(try engine.submitOffer(300, from: a))
    }

    func testOnlyTheTopBettorResolvesOffers() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(200, from: a)
        let offerID = engine.offers[0].id

        XCTAssertThrowsError(try engine.resolve(offer: offerID, as: .accepted, by: c)) { error in
            XCTAssertEqual(error as? GameError, .notTopBettor)
        }
        try engine.resolve(offer: offerID, as: .accepted, by: b)
        XCTAssertEqual(engine.offers[0].resolution, .accepted)
    }

    func testAResolvedOfferIsFinal() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(200, from: a)
        let offerID = engine.offers[0].id

        try engine.resolve(offer: offerID, as: .rejected, by: b)
        XCTAssertThrowsError(try engine.resolve(offer: offerID, as: .accepted, by: b)) { error in
            XCTAssertEqual(error as? GameError, .offerAlreadyResolved)
        }
    }

    func testAcceptingAnOfferPullsTheSenderOutOfTheRound() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(200, from: a)

        XCTAssertEqual(engine.entrants, [a, b])
        try engine.resolve(offer: engine.offers[0].id, as: .accepted, by: b)
        XCTAssertEqual(engine.entrants, [b], "an accepted offer is a withdrawal")
    }

    func testRejectingAnOfferKeepsTheSenderIn() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(200, from: a)

        try engine.resolve(offer: engine.offers[0].id, as: .rejected, by: b)
        XCTAssertEqual(engine.entrants, [a, b])
    }

    // MARK: - Settlement

    func testWinnerCollectsWhatTheLosersForfeit() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(2000, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        let bets = engine.participation
        let outcome = try engine.endRound()
        let winner = try XCTUnwrap(outcome.winner)
        let loser = winner == a ? b : a
        let forfeited = bets[loser]!.bet

        XCTAssertEqual(outcome.coinChanges[winner], forfeited)
        XCTAssertEqual(outcome.coinChanges[loser], -forfeited)
        XCTAssertEqual(engine.players[winner]!.coins, GameRules.startingCoins + forfeited)
        XCTAssertEqual(engine.players[loser]!.coins, GameRules.startingCoins - forfeited)
    }

    /// The spec's own worked example: one player in for 100, another for 2000,
    /// and the winner takes 2000.
    func testTheSpecsWorkedPayoutExample() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(2000, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        let outcome = try engine.endRound()
        if outcome.winner == a {
            XCTAssertEqual(outcome.coinChanges[a], 2000, "beating the big bet wins the big bet")
        } else {
            XCTAssertEqual(outcome.coinChanges[b], 100)
        }
    }

    func testConservingPayoutKeepsTheCoinSupplyConstant() throws {
        var engine = makeEngine(payout: .conserving)
        let supply = engine.players.values.reduce(0) { $0 + $1.coins }

        for _ in 0..<40 {
            try engine.startRound()
            var seatIndex = 0
            try runBetting(&engine) { _, _, range in
                defer { seatIndex += 1 }
                guard !range.isEmpty else { return .withdraw }
                return seatIndex.isMultiple(of: 2) ? .bet(range.minimum) : .withdraw
            }
            if case .negotiation = engine.phase { try engine.endRound() }
            XCTAssertEqual(
                engine.players.values.reduce(0) { $0 + $1.coins },
                supply,
                "coins were created or destroyed"
            )
        }
    }

    /// The original game's arithmetic, kept as an option: the winner takes the
    /// round's top bet whatever they staked themselves.
    func testTopBetToWinnerPayoutPaysTheTopBet() throws {
        var engine = makeEngine(payout: .topBetToWinner)
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(2000, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        let outcome = try engine.endRound()
        let winner = try XCTUnwrap(outcome.winner)
        XCTAssertEqual(outcome.coinChanges[winner], 2000, "the winner takes the top bet, whatever they staked")
    }

    /// Why `.topBetToWinner` is not the default: when the top bettor wins,
    /// their own stake is never deducted, so the table gains coins out of
    /// nothing. Compounded over a session this overflows `Int`.
    func testTopBetToWinnerPayoutMintsCoinsWhenTheTopBettorWins() throws {
        for seed in UInt64(0)..<200 {
            var engine = makeEngine(seed: seed, payout: .topBetToWinner)
            let supply = engine.players.values.reduce(0) { $0 + $1.coins }

            try engine.startRound()
            try engine.bet(100, from: a)
            try engine.bet(2000, from: b)
            try engine.withdraw(c)
            try engine.withdraw(d)

            let outcome = try engine.endRound()
            guard outcome.winner == engine.topBettor else { continue }

            XCTAssertEqual(outcome.coinChanges[b], 2000)
            XCTAssertEqual(outcome.coinChanges[a], -100)
            XCTAssertGreaterThan(
                engine.players.values.reduce(0) { $0 + $1.coins },
                supply,
                "the top bettor winning mints coins"
            )
            return
        }
        XCTFail("no seed in range let the top bettor win")
    }

    /// The default payout has no such hole, whoever wins.
    func testConservingPayoutNeverMintsCoins() throws {
        for seed in UInt64(0)..<50 {
            var engine = makeEngine(seed: seed, payout: .conserving)
            let supply = engine.players.values.reduce(0) { $0 + $1.coins }

            try engine.startRound()
            try engine.bet(100, from: a)
            try engine.bet(2000, from: b)
            try engine.withdraw(c)
            try engine.withdraw(d)
            try engine.endRound()

            XCTAssertEqual(engine.players.values.reduce(0) { $0 + $1.coins }, supply)
        }
    }

    func testTheStrongerHandWins() throws {
        // Scan seeds until one deals two clearly different hands to A and B,
        // then check the engine agrees with the scores.
        var engine = makeEngine(seed: 11)
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(200, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        let scoreA = engine.participation[a]!.hand.score
        let scoreB = engine.participation[b]!.hand.score
        let outcome = try engine.endRound()

        if scoreA != scoreB {
            XCTAssertEqual(outcome.winner, scoreA > scoreB ? a : b)
        }
        XCTAssertEqual(outcome.revealedHands.count, 2, "only entrants are revealed")
    }

    func testOnlyEntrantsAreRevealed() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.withdraw(b)
        try engine.withdraw(c)
        try engine.withdraw(d)

        let outcome = try engine.endRound()
        XCTAssertEqual(Set(outcome.revealedHands.keys), [a])
        XCTAssertEqual(outcome.winner, a, "the last player standing wins uncontested")
    }

    func testWithdrawnPlayersNeitherWinNorLose() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.withdraw(b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.endRound()

        XCTAssertEqual(engine.players[b]!.coins, GameRules.startingCoins)
        XCTAssertEqual(engine.players[c]!.coins, GameRules.startingCoins)
        XCTAssertEqual(engine.players[d]!.coins, GameRules.startingCoins)
    }

    func testAnAcceptedOfferIsPaidWhenTheTopBettorWins() throws {
        // A offers its way out; B is the top bettor and, alone at the reveal,
        // must win — so the offer is collected.
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(300, from: a)
        try engine.resolve(offer: engine.offers[0].id, as: .accepted, by: b)

        let outcome = try engine.endRound()
        XCTAssertEqual(outcome.winner, b)
        XCTAssertEqual(outcome.settledOffers.count, 1)
        XCTAssertEqual(outcome.coinChanges[a], -300, "the offer is the only thing A pays")
        XCTAssertEqual(outcome.coinChanges[b], 300, "B is alone at the reveal, so the offer is the whole take")
        XCTAssertEqual(engine.players[a]!.coins, GameRules.startingCoins - 300)
    }

    func testAnAcceptedOfferIsFreeWhenTheTopBettorLoses() throws {
        // C offers its way out and B accepts, but A outbid nobody — B only
        // collects if B wins, so scan for a seed where B does not.
        for seed in UInt64(0)..<200 {
            var engine = makeEngine(seed: seed)
            try engine.startRound()
            try engine.bet(100, from: a)
            try engine.bet(500, from: b)
            try engine.bet(600, from: c)
            try engine.withdraw(d)

            // C is top bettor here; A and B may offer out. Have A offer.
            guard engine.topBettor == c else { continue }
            try engine.submitOffer(200, from: a)
            try engine.resolve(offer: engine.offers[0].id, as: .accepted, by: c)

            let outcome = try engine.endRound()
            guard outcome.winner != c else { continue }

            XCTAssertTrue(outcome.settledOffers.isEmpty, "a losing top bettor collects nothing")
            XCTAssertEqual(outcome.coinChanges[a] ?? 0, 0, "A withdrew via the offer and pays nothing")
            XCTAssertEqual(engine.players[a]!.coins, GameRules.startingCoins)
            return
        }
        XCTFail("no seed in range produced a losing top bettor")
    }

    // MARK: - Round lifecycle

    func testEndRoundOnlyWorksDuringNegotiation() throws {
        var engine = makeEngine()
        try engine.startRound()
        XCTAssertThrowsError(try engine.endRound()) { error in
            XCTAssertEqual(error as? GameError, .wrongPhase)
        }
    }

    func testANewRoundClearsTheLastOne() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(500, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        try engine.submitOffer(200, from: a)
        try engine.endRound()

        try engine.startRound()
        XCTAssertTrue(engine.offers.isEmpty)
        XCTAssertEqual(engine.highestBet, 0)
        XCTAssertNil(engine.topBettor)
        XCTAssertTrue(engine.participation.values.allSatisfy { $0.bet == 0 && !$0.hasWithdrawn })
        XCTAssertEqual(engine.roundIndex, 1)
        XCTAssertEqual(engine.phase, .betting(seat: .east), "the deal has rotated")
    }

    func testRoundIndexAdvancesEvenWhenNobodyPlays() throws {
        var engine = makeEngine()
        try engine.startRound()
        try runBetting(&engine) { _, _, _ in .withdraw }
        XCTAssertEqual(engine.roundIndex, 1)
        try engine.startRound()
        XCTAssertEqual(engine.phase, .betting(seat: .east))
    }

    func testLeaderboardRanksByCoins() throws {
        var engine = makeEngine()
        try engine.startRound()
        try engine.bet(100, from: a)
        try engine.bet(2000, from: b)
        try engine.withdraw(c)
        try engine.withdraw(d)
        let outcome = try engine.endRound()

        let board = engine.leaderboard
        XCTAssertEqual(board.first?.id, outcome.winner)
        XCTAssertEqual(board.map(\.coins), board.map(\.coins).sorted(by: >))
    }

    /// Many rounds driven by the AI must never corrupt the table: no negative
    /// stacks, no duplicate cards, a constant coin supply, and the phase
    /// always advancing to the reveal.
    func testManyAIDrivenRoundsStayConsistent() throws {
        var engine = makeEngine(seed: 99)
        var ai = AIStrategy(seed: 99)
        let supply = engine.players.values.reduce(0) { $0 + $1.coins }

        for _ in 0..<200 {
            try engine.startRound()

            let dealt = engine.participation.values.flatMap(\.hand.cards)
            XCTAssertEqual(Set(dealt).count, 16)

            try runBetting(&engine) { _, hand, range in
                ai.decideBet(hand: hand, range: range)
            }

            if case .negotiation = engine.phase {
                for id in engine.entrants where id != engine.topBettor {
                    let hand = engine.participation[id]!.hand
                    if let amount = ai.decideOffer(hand: hand, range: engine.offerRange(for: id)) {
                        try engine.submitOffer(amount, from: id)
                    }
                }
                if let top = engine.topBettor {
                    let topHand = engine.participation[top]!.hand
                    for offer in engine.offers where offer.isPending {
                        let call = ai.decideOfferResolution(hand: topHand, offer: offer)
                        try engine.resolve(offer: offer.id, as: call, by: top)
                    }
                }
                try engine.endRound()
            }

            guard case .reveal = engine.phase else {
                return XCTFail("round did not reach reveal, stuck at \(engine.phase)")
            }
            for player in engine.players.values {
                XCTAssertGreaterThanOrEqual(player.coins, 0, "\(player.name) went into debt")
            }
            XCTAssertEqual(
                engine.players.values.reduce(0) { $0 + $1.coins },
                supply,
                "the default payout must conserve coins"
            )
        }
    }
}
