import XCTest
@testable import CardGame

/// Sharah (SPEC.md §9): money for leaving the round, settled the moment it is
/// accepted, with no effect on hands or on the showdown.
final class SharahTests: XCTestCase {

    /// Three players with room to raise, betting 500 / 1,500 / 2,500, left in
    /// negotiation.
    private func negotiating(seed: UInt64 = 21) throws -> GameEngine {
        var engine = GameEngine(players: table(3, balance: 20_000), seed: seed)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .bet(1_500), .bet(2_500)])
        XCTAssertEqual(engine.phase, .negotiation)
        return engine
    }

    func testAcceptedOfferMovesTheMoneyAtOnce() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let before = (payer: engine.players[payer]!.balance, taker: engine.players[taker]!.balance)

        let id = try engine.offerSharah(600, from: payer, to: taker)
        XCTAssertEqual(engine.players[payer]?.balance, before.payer, "nothing moves on an offer alone")

        try engine.respondToSharah(id, accept: true, by: taker)
        XCTAssertEqual(engine.players[payer]?.balance, before.payer - 600)
        XCTAssertEqual(engine.players[taker]?.balance, before.taker + 600)
    }

    func testAccepterLeavesTheRoundAndKeepsTheirBet() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let bet = engine.bet(of: taker)
        XCTAssertEqual(bet, 1_500)

        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: true, by: taker)

        XCTAssertEqual(engine.standing(of: taker), .boughtOut)
        XCTAssertEqual(engine.bet(of: taker), bet, "the bet is neither refunded nor cleared")
        XCTAssertFalse(engine.playersInRound.contains(taker))

        let result = try engine.endRound()
        XCTAssertNil(result.ledger.losses[taker], "a bought-out player loses nothing")
        XCTAssertEqual(engine.players[taker]?.balance, 20_000 + 600, "only the Sharah money moved")
    }

    func testAccepterReachesNoShowdownAndKeepsTheirCardsHidden() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: true, by: taker)

        let result = try engine.endRound()
        XCTAssertNil(result.revealedHands[taker], "bought-out cards are never revealed")
        XCTAssertFalse(result.winners.contains(taker))
        XCTAssertNil(engine.hand(of: taker, asSeenBy: payer), "still hidden after the round")
        XCTAssertNotNil(engine.hand(of: taker, asSeenBy: taker), "they can still see their own")
    }

    func testSharahPaymentIsNotABetAndDoesNotRaiseTheHighestBet() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        XCTAssertEqual(engine.highestBet, 2_500)

        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: true, by: taker)
        XCTAssertEqual(engine.highestBet, 2_500, "a payment is not a bet")

        let result = try engine.endRound()
        XCTAssertEqual(result.highestBet, 2_500)
    }

    /// Buying out the biggest bettor does not shrink the prize: the highest
    /// bet of the round is still theirs.
    func testTheTopBettorsBetStillCountsAfterTheyAreBoughtOut() throws {
        var engine = try negotiating()
        let top = engine.topBettor!
        XCTAssertEqual(engine.bet(of: top), 2_500)
        let payer = engine.turnOrder[0]

        let id = try engine.offerSharah(600, from: payer, to: top)
        try engine.respondToSharah(id, accept: true, by: top)

        let result = try engine.endRound()
        XCTAssertFalse(result.revealedHands.keys.contains(top))
        XCTAssertEqual(result.highestBet, 2_500, "the bet counts whether or not its owner is still in")
        let winner = result.winners[0]
        XCTAssertEqual(result.reward(for: winner), 2_500)
        XCTAssertGreaterThan(2_500, engine.bet(of: winner), "the winner collects more than anyone still in bet")
    }

    func testRejectedOfferChangesNothing() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let before = engine.players.mapValues(\.balance)

        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: false, by: taker)

        XCTAssertEqual(engine.players.mapValues(\.balance), before)
        XCTAssertEqual(engine.standing(of: taker), .committed)
        XCTAssertEqual(engine.offers.first?.state, .rejected)
        XCTAssertTrue(engine.playersInRound.contains(taker))
    }

    func testOnlyTheRecipientMayAnswer() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let id = try engine.offerSharah(600, from: payer, to: taker)
        XCTAssertThrowsError(try engine.respondToSharah(id, accept: true, by: payer)) {
            XCTAssertEqual($0 as? GameError, .notTheOfferRecipient)
        }
    }

    func testAnOfferIsAnsweredOnlyOnce() throws {
        var engine = try negotiating()
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: false, by: taker)
        XCTAssertThrowsError(try engine.respondToSharah(id, accept: true, by: taker)) {
            XCTAssertEqual($0 as? GameError, .offerAlreadyResolved)
        }
    }

    func testCannotOfferToYourself() throws {
        var engine = try negotiating()
        let player = engine.turnOrder[0]
        XCTAssertThrowsError(try engine.offerSharah(500, from: player, to: player)) {
            XCTAssertEqual($0 as? GameError, .cannotOfferToSelf)
        }
    }

    func testCannotOfferToSomeoneWhoLeftTheRound() throws {
        var engine = GameEngine(players: table(3, balance: 20_000), seed: 4)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .fold, .bet(1_500)])
        let folded = engine.turnOrder[1]
        XCTAssertThrowsError(try engine.offerSharah(500, from: engine.turnOrder[0], to: folded)) {
            XCTAssertEqual($0 as? GameError, .notInRound)
        }
    }

    /// Money already on the round is at risk, so it cannot also be promised as
    /// a payment — which leaves an all-in player with nothing to offer.
    func testCannotPromiseMoneyAlreadyOnTheRound() throws {
        var engine = GameEngine(players: table(2, balance: 2_000), seed: 6)
        try engine.startBetting()
        try engine.runBetting([.allIn, .stayIn])
        let allIn = engine.turnOrder[0]
        XCTAssertEqual(engine.availableBalance(of: allIn), 0)
        XCTAssertThrowsError(try engine.offerSharah(100, from: allIn, to: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .cannotAffordSharah)
        }
    }

    func testOfferMustBePositive() throws {
        var engine = try negotiating()
        XCTAssertThrowsError(try engine.offerSharah(0, from: engine.turnOrder[0], to: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .illegalSharahAmount(0))
        }
    }

    /// The parts §8 leaves open are policy, not hard-coded. With the default
    /// policy any player in the round may be offered money; a stricter policy
    /// narrows it without touching the engine.
    func testWhoMayBeOfferedIsPolicyNotRule() throws {
        var open = try negotiating()
        XCTAssertNoThrow(try open.offerSharah(600, from: open.turnOrder[2], to: open.turnOrder[1]))

        var strict = GameEngine(
            players: table(3, balance: 20_000),
            policy: GamePolicy(sharah: SharahPolicy(onlyTopBettorMayBeOffered: true)),
            seed: 21
        )
        try strict.startBetting()
        try strict.runBetting([.stayIn, .bet(1_500), .bet(2_500)])
        XCTAssertThrowsError(try strict.offerSharah(600, from: strict.turnOrder[2], to: strict.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .sharahNotAllowedByPolicy)
        }
        XCTAssertNoThrow(try strict.offerSharah(600, from: strict.turnOrder[0], to: strict.topBettor!))
    }

    func testSharahIsRejectedOutsideNegotiation() throws {
        var engine = GameEngine(players: table(3, balance: 20_000), seed: 9)
        try engine.startBetting()
        XCTAssertThrowsError(try engine.offerSharah(500, from: engine.turnOrder[0], to: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .wrongPhase)
        }

        try engine.runBetting([.stayIn, .stayIn, .stayIn])
        let id = try engine.offerSharah(500, from: engine.turnOrder[0], to: engine.turnOrder[1])
        try engine.endRound()
        XCTAssertThrowsError(try engine.respondToSharah(id, accept: true, by: engine.turnOrder[1])) {
            XCTAssertEqual($0 as? GameError, .wrongPhase)
        }
    }
}
