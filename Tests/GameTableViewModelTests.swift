import XCTest
@testable import CardGame

/// The table has to stay honest about the engine: what it shows is what the
/// round actually is, and what it hides stays hidden.
@MainActor
final class GameTableViewModelTests: XCTestCase {

    private func dealt(seed: UInt64) async -> GameTableViewModel {
        let model = GameTableViewModel(seed: seed, timing: .immediate)
        await model.startRound()
        return model
    }

    func testEverySeatIsDealtAFullHand() async {
        let model = await dealt(seed: 4)
        for seat in model.seats {
            XCTAssertEqual(model.dealtCards[seat], GameRules.handSize, "\(seat.label) is missing cards")
        }
        XCTAssertNotNil(model.hand(at: model.humanSeat))
    }

    /// The table must not draw a hand the human is not entitled to see.
    func testOpponentHandsAreNotAvailableToTheTable() async {
        let model = await dealt(seed: 7)
        guard case .betting = model.engine.phase else {
            return  // the human was not asked to act this round
        }
        for seat in model.seats where seat != model.humanSeat {
            XCTAssertNil(model.hand(at: seat), "\(seat.label)'s cards reached the view")
            XCTAssertFalse(model.showsFaces(at: seat))
        }
    }

    func testTheHumanIsOfferedOnlyLegalBets() async {
        let model = await dealt(seed: 7)
        guard case .betting(let turn) = model.engine.phase, turn == model.humanID else { return }
        XCTAssertEqual(model.interaction, .choosingAction)

        let range = model.humanBetRange
        XCTAssertEqual(range, model.engine.betRange(for: model.humanID!))
        XCTAssertFalse(model.humanBetOptions.isEmpty, "a full stack can always bet something")
        for amount in model.humanBetOptions {
            XCTAssertTrue(model.engine.isLegal(.bet(amount), for: model.humanID!), "\(amount) is illegal")
        }
        XCTAssertEqual(model.humanAllIn, model.human?.balance)
    }

    /// Plays the human's turn too, so the round reaches its end.
    private func playFullRound(seed: UInt64) async -> GameTableViewModel {
        let model = GameTableViewModel(seed: seed, timing: .immediate)
        await model.startRound()
        var guardRail = 0
        while guardRail < 20 {
            guardRail += 1
            switch model.interaction {
            case .choosingAction:
                // Cheapest way to stay in, so the round runs to a showdown.
                if let amount = model.humanBetOptions.first {
                    await model.take(.bet(amount))
                } else {
                    await model.take(.fold)
                }
            case .offeringSharah:
                await model.declineToOfferSharah()
            case .respondingToSharah(let offer):
                await model.respond(to: offer, accept: false)
            case .roundOver, .gameOver:
                return model
            case .watching, .readyToDeal:
                return model
            }
        }
        return model
    }

    func testARoundReachesAnOutcome() async {
        let model = await playFullRound(seed: 12)
        XCTAssertEqual(model.interaction, .roundOver)
        XCTAssertNotNil(model.result)
        XCTAssertTrue(model.engine.phase == .roundOver || model.engine.phase.handsAreRevealed)
    }

    func testFoldedSeatsLoseTheirCardsAndBubble() async {
        let model = await playFullRound(seed: 15)
        for seat in model.foldedSeats {
            XCTAssertNil(model.bubbles[seat], "a folded seat kept its bet bubble")
            XCTAssertFalse(model.showsFaces(at: seat) && seat != model.humanSeat)
        }
    }

    func testTheRevealShowsEveryHandThatReachedTheShowdown() async {
        let model = await playFullRound(seed: 18)
        guard let result = model.result else { return XCTFail("no result") }
        let revealed = Set(result.revealedHands.keys.compactMap { model.engine.seat(of: $0) })
        XCTAssertEqual(model.faceUpSeats, revealed)
        for seat in revealed {
            XCTAssertNotNil(model.hand(at: seat), "a revealed hand should be readable")
        }
    }

    func testBetBubblesMatchTheEngine() async {
        let model = await playFullRound(seed: 22)
        for seat in model.seats {
            guard let id = model.player(at: seat)?.id else { continue }
            let bet = model.engine.bet(of: id)
            if model.foldedSeats.contains(seat) || bet == 0 {
                XCTAssertNil(model.bubbles[seat])
            } else {
                XCTAssertEqual(model.bubbles[seat], bet, "\(seat.label)'s bubble is out of date")
            }
        }
    }

    /// The seat geometry has to place a thirteen-handed table as happily as a
    /// four-handed one, and put the human at the near edge either way.
    func testSeatLayoutScalesToAFullTable() {
        for count in [2, 4, 7, 13] {
            let seats = (0..<count).map(Seat.init)
            let layout = TableLayout(seats: seats, humanSeat: seats[0])
            XCTAssertEqual(layout.angle(of: seats[0]).degrees, 90, "the human sits at the bottom")
            XCTAssertEqual(layout.dominantSide(of: seats[0]), .bottom)

            let size = CGSize(width: 1_000, height: 600)
            let positions = seats.map { layout.position(of: $0, in: size, inset: 40) }
            XCTAssertEqual(Set(positions.map { "\(Int($0.x)),\(Int($0.y))" }).count, count, "two seats overlap")
            for point in positions {
                XCTAssertTrue((0...size.width).contains(point.x))
                XCTAssertTrue((0...size.height).contains(point.y))
            }
        }
    }

    func testFourHandedLayoutKeepsTheOriginalCompassPositions() {
        let seats = (0..<4).map(Seat.init)
        let layout = TableLayout(seats: seats, humanSeat: .south)
        XCTAssertEqual(layout.dominantSide(of: .south), .bottom)
        XCTAssertEqual(layout.dominantSide(of: .east), .right)
        XCTAssertEqual(layout.dominantSide(of: .north), .top)
        XCTAssertEqual(layout.dominantSide(of: .west), .left)
        XCTAssertEqual(layout.cardRotation(of: .south).degrees, 0)
        XCTAssertEqual(layout.cardRotation(of: .east).degrees, -90)
        XCTAssertEqual(layout.dealEdge(of: .south), .top)
        XCTAssertEqual(layout.bubbleImageName(of: .north), "upBubble")
    }
}

/// The near seat shares its edge with the control bar, so its fan has to be
/// placed around it rather than centred.
@MainActor
final class NearSeatLayoutTests: XCTestCase {

    private let size = CGSize(width: 874, height: 402)

    func testTheHumansFanClearsTheControlBar() {
        for count in [2, 4, 7, 13] {
            let seats = (0..<count).map(Seat.init)
            let layout = TableLayout(seats: seats, humanSeat: seats[0])
            let cardWidth: CGFloat = 76
            let reserved: CGFloat = 416

            let centre = layout.nearSeatPosition(
                in: size,
                cardWidth: cardWidth,
                reservedTrailingWidth: reserved
            )
            let rightEdge = centre.x + TableLayout.fanWidth(cardWidth: cardWidth) / 2
            XCTAssertLessThanOrEqual(
                rightEdge,
                size.width - reserved,
                "\(count)-handed: the fan runs under the controls"
            )
        }
    }

    func testTheFanStaysOnScreen() {
        let layout = TableLayout(seats: [Seat(0), Seat(1)], humanSeat: Seat(0))
        let cardWidth: CGFloat = 76
        // A control bar wider than the screen cannot push the cards off it.
        let centre = layout.nearSeatPosition(
            in: size,
            cardWidth: cardWidth,
            reservedTrailingWidth: size.width + 200
        )
        XCTAssertGreaterThanOrEqual(centre.x - TableLayout.fanWidth(cardWidth: cardWidth) / 2, 0)
    }

    func testAFanIsAsWideAsItsOverlapMakesIt() {
        // Four cards at 76pt, overlapping by 45% each: 76 + 3 x 41.8.
        XCTAssertEqual(TableLayout.fanWidth(cardWidth: 76), 76 + 3 * 76 * 0.55, accuracy: 0.01)
    }
}
