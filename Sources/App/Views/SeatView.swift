import SwiftUI

/// A seat's fan of cards, laid along its own edge of the table.
///
/// The old UI moved four separate image views with four constraint outlets per
/// player. Here a seat is one view that knows which edge it sits on.
struct SeatHandView: View {
    let seat: Seat
    let hand: Hand?
    let dealtCards: Int
    let faceUp: Bool
    let hasFolded: Bool
    var cardWidth: CGFloat = 76

    var body: some View {
        cards
            .rotationEffect(seat.cardRotation)
            .offset(foldOffset)
            .opacity(hasFolded ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: hasFolded)
    }

    private var cards: some View {
        let spacing = -cardWidth * 0.45
        return HStack(spacing: spacing) {
            ForEach(0..<GameRules.handSize, id: \.self) { index in
                if index < dealtCards {
                    CardView(card: hand?.sortedCards[index], faceUp: faceUp, width: cardWidth)
                        .rotationEffect(.degrees(fan(index)))
                        .transition(.asymmetric(
                            insertion: .move(edge: seat.dealEdge).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(Double(index))
                }
            }
        }
    }

    /// A gentle fan so overlapping cards stay readable.
    private func fan(_ index: Int) -> Double {
        let middle = Double(GameRules.handSize - 1) / 2
        return (Double(index) - middle) * 4
    }

    /// Where a folded hand slides to: off its own edge.
    private var foldOffset: CGSize {
        guard hasFolded else { return .zero }
        let distance = cardWidth * 2.4
        switch seat {
        case .south: return CGSize(width: 0, height: distance)
        case .north: return CGSize(width: 0, height: -distance)
        case .east: return CGSize(width: distance, height: 0)
        case .west: return CGSize(width: -distance, height: 0)
        }
    }
}

extension Seat {
    /// Cards face their own player.
    var cardRotation: Angle {
        switch self {
        case .south: return .degrees(0)
        case .east: return .degrees(-90)
        case .north: return .degrees(180)
        case .west: return .degrees(90)
        }
    }

    /// The edge a dealt card arrives from — the middle of the table.
    var dealEdge: Edge {
        switch self {
        case .south: return .top
        case .north: return .bottom
        case .east: return .leading
        case .west: return .trailing
        }
    }

    var label: String {
        switch self {
        case .south: return "South"
        case .east: return "East"
        case .north: return "North"
        case .west: return "West"
        }
    }
}
