import XCTest
@testable import CardGame

/// The dial's drop logic. The gesture itself cannot be driven in the
/// simulator while the device is held portrait — the control sits under iOS's
/// own edge gesture there — so the geometry is tested directly instead.
final class RadialDialTests: XCTestCase {

    private enum Destination: CaseIterable, Equatable {
        case first, second, third
    }

    private var dial: RadialDial<Destination> {
        RadialDial(destinations: Destination.allCases)
    }

    func testDestinationsFanOverAQuarterTurnUpAndRight() {
        let up = dial.offset(for: .first)
        XCTAssertEqual(up.width, 0, accuracy: 0.001)
        XCTAssertEqual(up.height, -84, accuracy: 0.001, "the first destination sits straight up")

        let right = dial.offset(for: .third)
        XCTAssertEqual(right.width, 84, accuracy: 0.001, "the last sits straight out to the right")
        XCTAssertEqual(right.height, 0, accuracy: 0.001)

        let middle = dial.offset(for: .second)
        XCTAssertEqual(middle.width, 84 * cos(.pi / 4), accuracy: 0.001)
        XCTAssertEqual(middle.height, -84 * sin(.pi / 4), accuracy: 0.001)
    }

    func testEveryDestinationIsPickedByDroppingOnIt() {
        for destination in Destination.allCases {
            XCTAssertEqual(
                dial.destination(nearest: dial.offset(for: destination)),
                destination,
                "dropping on \(destination) should pick it"
            )
        }
    }

    func testDroppingNearADestinationStillPicksIt() {
        let target = dial.offset(for: .second)
        let nudged = CGSize(width: target.width + 20, height: target.height + 20)
        XCTAssertEqual(dial.destination(nearest: nudged), .second)
    }

    func testDroppingOnTheDotPicksNothing() {
        XCTAssertNil(dial.destination(nearest: .zero), "releasing without travelling selects nothing")
    }

    func testDroppingFarAwayPicksNothing() {
        XCTAssertNil(dial.destination(nearest: CGSize(width: -300, height: 300)))
    }

    func testTheNearestDestinationWinsWhenTwoAreInRange() {
        let first = dial.offset(for: .first)
        let second = dial.offset(for: .second)
        // Sit between the two, but closer to the second.
        let between = CGSize(
            width: first.width + (second.width - first.width) * 0.7,
            height: first.height + (second.height - first.height) * 0.7
        )
        XCTAssertEqual(dial.destination(nearest: between), .second)
    }

    func testASingleDestinationSitsStraightUp() {
        let single = RadialDial(destinations: [Destination.first])
        XCTAssertEqual(single.offset(for: .first), CGSize(width: 0, height: -84))
        XCTAssertEqual(single.destination(nearest: CGSize(width: 0, height: -84)), .first)
    }

    func testTheLiveDialCoversEveryPanel() {
        let panels = RadialDial(destinations: GameTableViewModel.Panel.allCases)
        for panel in GameTableViewModel.Panel.allCases {
            XCTAssertEqual(panels.destination(nearest: panels.offset(for: panel)), panel)
        }
    }
}
