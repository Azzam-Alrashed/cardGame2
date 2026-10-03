import SwiftUI

/// A seat's fan of cards, laid along its own edge of the table.
struct SeatHandView: View {
    let hand: Hand?
    let dealtCards: Int
    let faceUp: Bool
    let hasFolded: Bool
    /// Where this seat sits, so the fan faces its own player.
    let rotation: Angle
    let dealEdge: Edge
    var cardWidth: CGFloat = 76

    var body: some View {
        cards
            .rotationEffect(rotation)
            .offset(foldOffset)
            .opacity(hasFolded ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: hasFolded)
    }

    private var cards: some View {
        let spacing = -cardWidth * 0.45
        return HStack(spacing: spacing) {
            ForEach(0..<GameRules.handSize, id: \.self) { index in
                if index < dealtCards {
                    CardView(card: card(index), faceUp: faceUp, width: cardWidth)
                        .rotationEffect(.degrees(fan(index)))
                        .transition(.asymmetric(
                            insertion: .move(edge: dealEdge).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(Double(index))
                }
            }
        }
    }

    /// Nil for a hand this player is not entitled to see, which draws a back.
    private func card(_ index: Int) -> Card? {
        guard let hand, index < hand.sortedCards.count else { return nil }
        return hand.sortedCards[index]
    }

    /// A gentle fan so overlapping cards stay readable.
    private func fan(_ index: Int) -> Double {
        let middle = Double(GameRules.handSize - 1) / 2
        return (Double(index) - middle) * 4
    }

    /// Where a folded hand slides to: away from the middle of the table.
    private var foldOffset: CGSize {
        guard hasFolded else { return .zero }
        let distance = cardWidth * 2.4
        switch dealEdge {
        case .top: return CGSize(width: 0, height: distance)
        case .bottom: return CGSize(width: 0, height: -distance)
        case .leading: return CGSize(width: distance, height: 0)
        case .trailing: return CGSize(width: -distance, height: 0)
        }
    }
}
