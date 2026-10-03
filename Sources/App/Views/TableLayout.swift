import SwiftUI

/// Where each seat sits round the table.
///
/// The old table hard-coded four compass positions, which cannot lay out a
/// table of up to thirteen. Seats are now placed on an ellipse: the human at
/// the near edge, everyone else spaced evenly round it in the direction the
/// cards are dealt. A four-handed table lands on the same four positions the
/// compass cases used, so the original layout is unchanged.
struct TableLayout {
    let seats: [Seat]
    let humanSeat: Seat

    /// Screen angle of a seat, measured clockwise from the right-hand edge —
    /// so 90° is the bottom of the screen, where the human sits.
    func angle(of seat: Seat) -> Angle {
        let count = seats.count
        guard count > 0,
              let index = seats.firstIndex(of: seat),
              let human = seats.firstIndex(of: humanSeat)
        else { return .degrees(90) }
        let offset = (index - human + count) % count
        return .degrees(90 - 360 * Double(offset) / Double(count))
    }

    /// A point on an ellipse inset into `size` by `inset`, scaled toward the
    /// middle by `pull`.
    func position(of seat: Seat, in size: CGSize, inset: CGFloat, pull: CGFloat = 1) -> CGPoint {
        let radians = angle(of: seat).radians
        let rx = max(0, size.width / 2 - inset) * pull
        let ry = max(0, size.height / 2 - inset) * pull
        return CGPoint(
            x: size.width / 2 + rx * cos(radians),
            y: size.height / 2 + ry * sin(radians)
        )
    }

    /// Cards face their own player: a seat at the bottom reads upright, one at
    /// the top is upside down.
    func cardRotation(of seat: Seat) -> Angle {
        .degrees(angle(of: seat).degrees - 90)
    }

    /// The edge a dealt card flies in from — whichever side of this seat the
    /// middle of the table is on.
    func dealEdge(of seat: Seat) -> Edge {
        switch dominantSide(of: seat) {
        case .bottom: return .top
        case .top: return .bottom
        case .right: return .leading
        case .left: return .trailing
        }
    }

    /// The speech-bubble art that points toward this seat.
    func bubbleImageName(of seat: Seat) -> String {
        switch dominantSide(of: seat) {
        case .bottom: return "downBubble"
        case .top: return "upBubble"
        case .right: return "rightBubble"
        case .left: return "leftBubble"
        }
    }

    /// Where the human's own fan goes.
    ///
    /// The control bar takes the bottom-trailing corner, so the near seat's
    /// cards are pulled toward the leading edge until the whole fan clears it.
    /// Before the missing card art was drawn this never showed: three of the
    /// four cards rendered as nothing, so the fan looked narrow enough to fit.
    ///
    /// - Parameters:
    ///   - cardWidth: width of one card in the fan.
    ///   - reservedTrailingWidth: width of the controls, including their
    ///     padding, measured from the trailing edge.
    func nearSeatPosition(
        in size: CGSize,
        cardWidth: CGFloat,
        reservedTrailingWidth: CGFloat
    ) -> CGPoint {
        let base = position(of: humanSeat, in: size, inset: cardWidth * 0.9)
        let halfFan = Self.fanWidth(cardWidth: cardWidth) / 2
        let clearOfControls = size.width - reservedTrailingWidth - halfFan - cardWidth * 0.1
        // Never push the fan off the leading edge to make room.
        let x = max(halfFan, min(base.x, clearOfControls))
        return CGPoint(x: x, y: base.y)
    }

    /// How wide a four-card fan is, at the overlap `SeatHandView` draws with.
    static func fanWidth(cardWidth: CGFloat) -> CGFloat {
        let overlap = cardWidth * 0.45
        return cardWidth * CGFloat(GameRules.handSize) - overlap * CGFloat(GameRules.handSize - 1)
    }

    enum Side { case top, bottom, left, right }

    /// Which edge of the table a seat is nearest.
    func dominantSide(of seat: Seat) -> Side {
        let radians = angle(of: seat).radians
        if abs(cos(radians)) > abs(sin(radians)) {
            return cos(radians) > 0 ? .right : .left
        }
        return sin(radians) > 0 ? .bottom : .top
    }
}
