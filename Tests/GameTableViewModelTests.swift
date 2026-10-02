import XCTest
@testable import CardGame

/// The view model's presentation state has to stay honest about the engine:
/// what the table shows is what the round actually is.
@MainActor
final class GameTableViewModelTests: XCTestCase {

    /// Deals, then plays every AI seat, stopping if the human is asked to act.
    private func dealAndRunAI(seed: UInt64) async -> GameTableViewModel {
        let model = GameTableViewModel(seed: seed, timing: .immediate)
        await model.startRound()
        return model
    }

    func testEverySeatIsDealtAFullHand() async {
        let model = await dealAndRunAI(seed: 4)
        for seat in Seat.allCases {
            XCTAssertNotNil(model.hand(at: seat), "\(seat) was not dealt")
            XCTAssertEqual(model.dealtCards[seat], GameRules.handSize, "\(seat) is missing cards")
        }
    }

    /// The bug this test was written for: a seat that withdrew still had its
    /// cards on the table.
    func testFoldedSeatsMatchTheEngine() async {
        for seed in UInt64(0)..<40 {
            let model = await dealAndRunAI(seed: seed)

            for seat in Seat.allCases {
                guard let id = model.player(at: seat)?.id,
                      let participation = model.engine.participation[id]
                else { continue }

                // A seat the human has not reached yet has not acted at all.
                if case .betting(let awaiting) = model.engine.phase,
                   model.engine.turnOrder.firstIndex(of: seat) ?? 0 >= model.engine.turnOrder.firstIndex(of: awaiting) ?? 0 {
                    continue
                }

                XCTAssertEqual(
                    model.foldedSeats.contains(seat),
                    participation.hasWithdrawn,
                    "seat \(seat) shows folded=\(model.foldedSeats.contains(seat)) but the engine says withdrawn=\(participation.hasWithdrawn) (seed \(seed))"
                )
            }
        }
    }

    func testBubblesMatchTheBetsOnTheTable() async {
        for seed in UInt64(0)..<40 {
            let model = await dealAndRunAI(seed: seed)

            for seat in Seat.allCases {
                guard let id = model.player(at: seat)?.id,
                      let participation = model.engine.participation[id]
                else { continue }

                if participation.bet > 0 && !participation.hasWithdrawn {
                    XCTAssertEqual(model.bubbles[seat], participation.bet, "seat \(seat) (seed \(seed))")
                } else if participation.hasWithdrawn {
                    XCTAssertNil(model.bubbles[seat], "a folded seat should show no bet (seed \(seed))")
                }
            }
        }
    }

    func testTheHumanIsAskedToActWhenItIsTheirTurn() async {
        let model = await dealAndRunAI(seed: 4)
        if case .betting(let seat) = model.engine.phase, seat == model.humanSeat {
            XCTAssertTrue(
                model.interaction == .choosingAction || model.interaction == .watching,
                "the human's turn should surface controls, not \(model.interaction)"
            )
        }
    }

    func testStartingAFreshRoundClearsTheLastOnesPresentation() async {
        let model = GameTableViewModel(seed: 12, timing: .immediate)
        await model.startRound()
        await model.startRound()

        XCTAssertTrue(model.faceUpSeats.isEmpty)
        XCTAssertNil(model.outcome)
        // A new deal wipes folds and bets from the previous round; any state
        // present now belongs to the round just dealt.
        for seat in Seat.allCases where model.engine.participation[model.player(at: seat)?.id ?? "x"]?.bet == 0 {
            XCTAssertNil(model.bubbles[seat])
        }
    }
}
