import XCTest
@testable import CardGame

/// The AI (SPEC.md §10, §11). The thing being tested is mostly a negative: a
/// bet must not be a reliable signal of a hand.
final class AIStrategyTests: XCTestCase {

    private func emptyTable(
        viewer: PlayerID = "me",
        highestBet: Int = 0,
        opponents: Int = 3,
        opponentsFolded: Int = 0
    ) -> PublicTableView {
        var players: [PublicPlayerView] = [
            PublicPlayerView(
                id: viewer, name: "me", seat: Seat(0), balance: 5_000, bet: 0,
                standing: .yetToAct, isEliminated: false, isTopBettor: false, hand: nil
            )
        ]
        for index in 0..<opponents {
            players.append(PublicPlayerView(
                id: PlayerID("o\(index)"), name: "o\(index)", seat: Seat(index + 1),
                balance: 5_000, bet: highestBet, standing: index < opponentsFolded ? .folded : .committed,
                isEliminated: false, isTopBettor: index == 0 && highestBet > 0, hand: nil
            ))
        }
        return PublicTableView(
            viewer: viewer,
            phase: .betting(turn: viewer),
            roundIndex: 0,
            players: players,
            highestBet: highestBet,
            requiredBet: BettingRules.required(standingBet: highestBet),
            topBettor: highestBet > 0 ? "o0" : nil,
            offers: []
        )
    }

    /// Runs `count` decisions, each from a different seed, and reports what
    /// came back.
    private func sample(
        hand: Hand,
        balance: Int = 5_000,
        personality: AIStrategy.Personality = .balanced,
        table: PublicTableView,
        count: Int = 200
    ) -> [BetAction] {
        (0..<count).map { seed in
            var ai = AIStrategy(personality: personality, seed: UInt64(seed) + 1)
            return ai.decideBet(hand: hand, balance: balance, table: table)
        }
    }

    /// A bet above the cheapest way to stay in, or a shove.
    private func isLoud(_ action: BetAction) -> Bool {
        switch action {
        case .allIn: return true
        case .bet(let amount): return amount > BettingRules.required(standingBet: 0)
        case .fold: return false
        }
    }

    /// Bet sizes a sample produced, for comparing one hand against another.
    private func amounts(_ actions: [BetAction]) -> Set<Int> {
        Set(actions.compactMap { action -> Int? in
            if case .bet(let amount) = action { return amount }
            return nil
        })
    }

    func testHandStrengthRespectsTheHierarchy() {
        let quads = AIStrategy.handStrength(hand(.two, .two, .two, .two))
        let trips = AIStrategy.handStrength(hand(.ace, .ace, .ace, .king))
        let pair = AIStrategy.handStrength(hand(.ace, .ace, .king, .queen))
        let rainbow = AIStrategy.handStrength(hand(.ace, .king, .queen, .jack))
        XCTAssertGreaterThan(quads, trips)
        XCTAssertGreaterThan(trips, pair)
        XCTAssertGreaterThan(pair, rainbow)
    }

    /// A weak hand still bets sometimes — that is the bluff, and without it the
    /// table could read every opponent perfectly.
    func testItBluffsWithNothing() {
        let actions = sample(hand: hand(.five, .four, .three, .two), table: emptyTable())
        let plays = actions.filter { $0 != .fold }
        XCTAssertFalse(plays.isEmpty, "a weak hand must sometimes bet anyway")
        XCTAssertTrue(plays.contains { isLoud($0) }, "a bluff should sometimes be loud")
    }

    /// And a strong hand sometimes keeps quiet, so a small bet is no safer to
    /// read than a large one.
    func testItUnderbetsAMonsterSometimes() {
        let actions = sample(hand: hand(.ace, .ace, .ace, .ace), table: emptyTable())
        XCTAssertTrue(actions.contains(.bet(500)), "four aces should sometimes bet the minimum")
        XCTAssertTrue(actions.contains { isLoud($0) }, "and sometimes not")
    }

    func testStrongHandsStillPlayMoreOftenThanWeakOnes() {
        let strong = sample(hand: hand(.ace, .ace, .ace, .king), table: emptyTable())
            .filter { $0 != .fold }.count
        let weak = sample(hand: hand(.six, .four, .three, .two), table: emptyTable())
            .filter { $0 != .fold }.count
        XCTAssertGreaterThan(strong, weak, "strength should still tilt the odds")
    }

    func testTwoOpponentsWithTheSameHandNeedNotAgree() {
        let actions = Set(sample(hand: hand(.king, .king, .nine, .four), table: emptyTable()))
        XCTAssertGreaterThan(actions.count, 1, "identical hands must be able to play differently")
    }

    func testBetSizeIsNotAFunctionOfHandStrength() {
        let strong = amounts(sample(hand: hand(.ace, .ace, .ace, .ace), balance: 20_000, table: emptyTable()))
        let weak = amounts(sample(hand: hand(.seven, .five, .four, .three), balance: 20_000, table: emptyTable()))
        XCTAssertFalse(strong.isEmpty)
        XCTAssertFalse(weak.isEmpty)
        XCTAssertFalse(
            strong.intersection(weak).isEmpty,
            "the same bet must be reachable from a monster and from nothing"
        )
    }

    /// With room to move, the AI uses more than one or two sizes — betting is
    /// a choice of amount, not a ladder of fixed steps.
    func testItPicksVariedBetSizesWhenItCanAffordThem() {
        let sizes = amounts(sample(hand: hand(.king, .king, .nine, .four), balance: 40_000, table: emptyTable()))
        XCTAssertGreaterThan(sizes.count, 2, "sizes were \(sizes.sorted())")
        XCTAssertTrue(sizes.allSatisfy { $0 % GameRules.betUnit == 0 }, "every bet is a whole 500")
    }

    func testItWeighsEliminationRisk() {
        let table = emptyTable(highestBet: 2_000)
        let comfortable = sample(hand: hand(.nine, .eight, .seven, .five), balance: 40_000, table: table)
            .filter { $0 == .fold }.count
        let desperate = sample(hand: hand(.nine, .eight, .seven, .five), balance: 2_500, table: table)
            .filter { $0 == .fold }.count
        XCTAssertGreaterThan(desperate, comfortable, "a short stack should fold a weak hand more often")
    }

    func testItOnlyEverPicksALegalAction() {
        for balance in [0, 400, 500, 1_200, 3_000, 50_000] {
            for highestBet in [0, 500, 2_000, 9_000] {
                let table = emptyTable(highestBet: highestBet)
                for action in sample(hand: hand(.ace, .king, .nine, .four), balance: balance, table: table, count: 40) {
                    XCTAssertTrue(
                        BettingRules.isLegal(action, standingBet: highestBet, balance: balance),
                        "\(action) is not legal on \(balance) against \(highestBet)"
                    )
                }
            }
        }
    }

    func testWithNothingLeftItCanOnlyFold() {
        XCTAssertEqual(sample(hand: hand(.ace, .ace, .ace, .ace), balance: 0, table: emptyTable(), count: 20), Array(repeating: .fold, count: 20))
    }

    // MARK: - Sharah

    func testItPaysToRemoveARivalOnlyWithSomethingWorthProtecting() {
        func offers(_ held: Hand) -> Int {
            (0..<120).reduce(into: 0) { count, seed in
                var ai = AIStrategy(personality: .balanced, seed: UInt64(seed) + 1)
                if ai.decideSharahOffer(hand: held, available: 5_000, table: emptyTable(highestBet: 1_000)) != nil {
                    count += 1
                }
            }
        }
        XCTAssertGreaterThan(offers(hand(.ace, .ace, .ace, .king)), offers(hand(.five, .four, .three, .two)))
    }

    func testItTakesTheMoneyMoreReadilyWithAWeakHand() {
        func accepts(_ held: Hand, amount: Int) -> Int {
            (0..<120).reduce(into: 0) { count, seed in
                var ai = AIStrategy(personality: .balanced, seed: UInt64(seed) + 1)
                let offer = SharahOffer(from: "o0", to: "me", amount: amount)
                if ai.respondToSharah(offer, hand: held, bet: 1_000, table: emptyTable(highestBet: 1_000)) {
                    count += 1
                }
            }
        }
        XCTAssertGreaterThan(
            accepts(hand(.five, .four, .three, .two), amount: 1_000),
            accepts(hand(.ace, .ace, .ace, .ace), amount: 1_000)
        )
        XCTAssertGreaterThan(
            accepts(hand(.nine, .eight, .seven, .five), amount: 2_000),
            accepts(hand(.nine, .eight, .seven, .five), amount: 100),
            "more money should be more tempting"
        )
    }

    func testItNeverOffersMoreThanItHas() {
        for available in [0, 1, 50, 5_000] {
            for seed in UInt64(0)..<40 {
                var ai = AIStrategy(personality: .reckless, seed: seed + 1)
                let offer = ai.decideSharahOffer(
                    hand: hand(.ace, .ace, .ace, .ace),
                    available: available,
                    table: emptyTable(highestBet: 1_000)
                )
                if let offer {
                    XCTAssertGreaterThan(offer.amount, 0)
                    XCTAssertLessThanOrEqual(offer.amount, available)
                }
            }
        }
    }
}
