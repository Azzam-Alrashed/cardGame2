import XCTest
@testable import CardGame

/// Imperfect information (SPEC.md §4, §10). A hand belongs to its owner until
/// the showdown reveals it, and a hand that left the round is never revealed.
final class InformationSecurityTests: XCTestCase {

    func testAPlayerSeesOnlyTheirOwnHandDuringBetting() throws {
        var engine = GameEngine(players: table(4), seed: 31)
        try engine.startBetting()

        for viewer in engine.turnOrder {
            XCTAssertNotNil(engine.hand(of: viewer, asSeenBy: viewer), "a player must see their own cards")
            for other in engine.turnOrder where other != viewer {
                XCTAssertNil(
                    engine.hand(of: other, asSeenBy: viewer),
                    "\(viewer) could see \(other)'s hand"
                )
            }
        }
        XCTAssertTrue(engine.revealedHands.isEmpty, "nothing is revealed before the showdown")
    }

    func testThePublicViewCarriesNoOpponentHands() throws {
        var engine = GameEngine(players: table(4), seed: 32)
        try engine.startBetting()

        for viewer in engine.turnOrder {
            let table = engine.publicView(for: viewer)
            XCTAssertNotNil(table.player(viewer)?.hand, "the viewer's own hand is theirs to see")
            for opponent in table.opponents {
                XCTAssertNil(opponent.hand, "\(opponent.id)'s hand leaked to \(viewer)")
            }
        }
    }

    /// What the public view *does* carry: bets, standings, balances, offers.
    /// That is the whole of what a bluff has to work with.
    func testThePublicViewCarriesTheActions() throws {
        var engine = GameEngine(players: table(3), seed: 33)
        try engine.startBetting()
        try engine.runBetting([.bet(1_500), .fold, .stayIn])

        let table = engine.publicView(for: engine.turnOrder[0])
        XCTAssertEqual(table.highestBet, 1_500)
        XCTAssertEqual(table.player(engine.turnOrder[1])?.standing, .folded)
        XCTAssertEqual(table.player(engine.turnOrder[2])?.bet, 1_500)
        XCTAssertEqual(table.opponentsOut, 1)
    }

    func testTheShowdownRevealsOnlyThePlayersStillIn() throws {
        var engine = GameEngine(players: table(4), seed: 34)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .fold, .bet(1_000), .fold])
        let (stayed, folded) = (engine.turnOrder[0], engine.turnOrder[1])

        let result = try engine.endRound()
        XCTAssertNotNil(result.revealedHands[stayed])
        XCTAssertNil(result.revealedHands[folded], "a folded hand is never shown")
        XCTAssertNotNil(engine.hand(of: stayed, asSeenBy: folded), "revealed hands are public")
        XCTAssertNil(engine.hand(of: folded, asSeenBy: stayed), "a folded hand stays private for ever")
    }

    func testABoughtOutHandStaysPrivateThroughTheReveal() throws {
        var engine = GameEngine(players: table(3, balance: 20_000), seed: 35)
        try engine.startBetting()
        try engine.runBetting([.stayIn, .bet(1_500), .bet(2_500)])
        let (payer, taker) = (engine.turnOrder[2], engine.turnOrder[1])
        let id = try engine.offerSharah(600, from: payer, to: taker)
        try engine.respondToSharah(id, accept: true, by: taker)
        try engine.endRound()

        XCTAssertNil(engine.hand(of: taker, asSeenBy: payer))
        XCTAssertNil(engine.revealedHands[taker])
        XCTAssertTrue(engine.phase.handsAreRevealed, "the round did reach a reveal")
    }

    /// The AI is handed its own hand and a `PublicTableView`, and there is no
    /// path from either to a hidden card — so it cannot be reading one.
    func testTheAIIsOnlyEverGivenPublicInformation() throws {
        var engine = GameEngine(players: table(4), seed: 36)
        try engine.startBetting()
        let thinker = engine.turnOrder[0]
        let view = engine.publicView(for: thinker)

        XCTAssertEqual(view.opponents.count, 3)
        XCTAssertTrue(view.opponents.allSatisfy { $0.hand == nil })

        var ai = AIStrategy(personality: .balanced, seed: 1)
        let hand = engine.hand(of: thinker, asSeenBy: thinker)!
        let first = ai.decideBet(hand: hand, balance: 5_000, table: view)

        var replay = AIStrategy(personality: .balanced, seed: 1)
        let second = replay.decideBet(hand: hand, balance: 5_000, table: view)
        XCTAssertEqual(first, second, "the decision is a function of public state plus its own hand")
    }
}
