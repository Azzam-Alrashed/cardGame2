import XCTest
@testable import CardGame

final class AIStrategyTests: XCTestCase {

    private func hand(_ cards: [(Rank, Suit)]) -> Hand {
        Hand(cards: cards.map { Card($0.0, $0.1) })
    }

    private var fourAces: Hand { hand([(.ace, .spades), (.ace, .clubs), (.ace, .hearts), (.ace, .diamonds)]) }
    private var rainbow: Hand { hand([(.ace, .spades), (.king, .clubs), (.queen, .hearts), (.jack, .diamonds)]) }

    func testConfidenceSpansTheHandRange() {
        XCTAssertEqual(AIStrategy.confidence(in: fourAces), 1.0, accuracy: 0.0001)
        XCTAssertLessThan(AIStrategy.confidence(in: rainbow), 0.1)
    }

    func testItNeverBetsWithNoLegalOptions() {
        var ai = AIStrategy(seed: 1)
        XCTAssertEqual(ai.decideBet(hand: fourAces, range: .empty), .withdraw)
    }

    func testItAlwaysBetsAMonsterHandWhenItCannotFlinch() {
        var ai = AIStrategy(personality: .init(bluffChance: 0, flinchChance: 0), seed: 1)
        guard case .bet = ai.decideBet(hand: fourAces, range: StakeRange(minimum: 100, maximum: 300)) else {
            return XCTFail("four aces should always be played")
        }
    }

    func testItFoldsARainbowWhenItCannotBluff() {
        var ai = AIStrategy(personality: .init(bluffChance: 0, flinchChance: 0), seed: 1)
        XCTAssertEqual(ai.decideBet(hand: rainbow, range: StakeRange(minimum: 100, maximum: 300)), .withdraw)
    }

    func testBetIsAlwaysALegalOption() {
        var ai = AIStrategy(seed: 5)
        let range = StakeRange(minimum: 600, maximum: 1000)
        for _ in 0..<200 {
            if case .bet(let amount) = ai.decideBet(hand: fourAces, range: range) {
                XCTAssertTrue(range.contains(amount), "\(amount) is not a legal bet")
            }
        }
    }

    func testStrongerHandsBetMoreOnAverage() {
        var strongAI = AIStrategy(personality: .init(bluffChance: 0, flinchChance: 0), seed: 3)
        var weakAI = AIStrategy(personality: .init(bluffChance: 0, flinchChance: 0), seed: 3)
        let range = StakeRange(minimum: 100, maximum: 5000)
        let pair = hand([(.jack, .spades), (.jack, .clubs), (.queen, .hearts), (.king, .diamonds)])

        func total(_ ai: inout AIStrategy, _ h: Hand) -> Int {
            (0..<50).reduce(0) { sum, _ in
                if case .bet(let amount) = ai.decideBet(hand: h, range: range) { return sum + amount }
                return sum
            }
        }

        XCTAssertGreaterThan(total(&strongAI, fourAces), total(&weakAI, pair))
    }

    func testItKeepsAStrongHandRatherThanBuyingOut() {
        var ai = AIStrategy(seed: 2)
        XCTAssertNil(ai.decideOffer(hand: fourAces, range: StakeRange(minimum: 100, maximum: 300)))
    }

    func testItPaysToEscapeAWeakHand() {
        var ai = AIStrategy(seed: 2)
        let offer = ai.decideOffer(hand: rainbow, range: StakeRange(minimum: 100, maximum: 300))
        XCTAssertEqual(offer, 300, "the weakest hand should bid the most to get out")
    }

    func testOfferIsAlwaysALegalOption() {
        var ai = AIStrategy(seed: 4)
        let range = StakeRange(minimum: 100, maximum: 400)
        let hands = [rainbow, hand([(.jack, .spades), (.jack, .clubs), (.queen, .hearts), (.king, .diamonds)])]
        for h in hands {
            if let offer = ai.decideOffer(hand: h, range: range) {
                XCTAssertTrue(range.contains(offer))
            }
        }
    }

    func testSameSeedGivesTheSameDecisions() {
        var first = AIStrategy(seed: 123)
        var second = AIStrategy(seed: 123)
        let range = StakeRange(minimum: 100, maximum: 500)
        let marginal = hand([(.queen, .spades), (.queen, .clubs), (.king, .hearts), (.jack, .diamonds)])
        for _ in 0..<50 {
            XCTAssertEqual(
                first.decideBet(hand: marginal, range: range),
                second.decideBet(hand: marginal, range: range)
            )
        }
    }

    func testPersonalitiesDifferInAggression() {
        let range = StakeRange(minimum: 100, maximum: 5000)
        let marginal = hand([(.king, .spades), (.king, .clubs), (.queen, .hearts), (.jack, .diamonds)])

        func committed(_ personality: AIStrategy.Personality) -> Int {
            var ai = AIStrategy(personality: personality, seed: 77)
            return (0..<100).reduce(0) { sum, _ in
                if case .bet(let amount) = ai.decideBet(hand: marginal, range: range) { return sum + amount }
                return sum
            }
        }

        XCTAssertGreaterThan(committed(.reckless), committed(.cautious))
    }
}
