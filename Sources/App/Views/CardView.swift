import SwiftUI
import UIKit

/// Which picture, if any, the asset catalog has for a card.
///
/// The art was drawn for the old 16-card deck, so only A, K, Q and J exist as
/// images — the 36 faces from 10 down to 2 have none. A missing `Image(_:)`
/// draws nothing at all, which is why a hand of A 9 7 3 used to show one card
/// and three gaps. Every card now resolves to something: its artwork when there
/// is any, and a drawn face when there is not.
enum CardArt {
    case artwork(String)
    case drawn

    static func representation(for card: Card) -> CardArt {
        hasArtwork(named: card.imageName) ? .artwork(card.imageName) : .drawn
    }

    static func back() -> CardArt {
        hasArtwork(named: "back_red") ? .artwork("back_red") : .drawn
    }

    /// Whether the asset catalog actually holds this image.
    static func hasArtwork(named name: String) -> Bool {
        UIImage(named: name) != nil
    }
}

/// One playing card, face up or face down, at the deck's 2:3 proportions.
struct CardView: View {
    let card: Card?
    var faceUp: Bool = true
    var width: CGFloat = 76

    /// The proportions the original art was drawn at.
    static let aspectRatio: CGFloat = 2 / 3

    private var height: CGFloat { width / Self.aspectRatio }

    var body: some View {
        content
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: width * 0.09))
            .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }

    @ViewBuilder
    private var content: some View {
        switch representation {
        case .artwork(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .drawn:
            if faceUp, let card {
                DrawnCardFace(card: card, width: width)
            } else {
                DrawnCardBack(width: width)
            }
        }
    }

    private var representation: CardArt {
        guard faceUp, let card else { return CardArt.back() }
        return CardArt.representation(for: card)
    }
}

/// A card face drawn from its rank and suit, for the ranks the asset catalog
/// has no picture of.
struct DrawnCardFace: View {
    let card: Card
    let width: CGFloat

    private var colour: Color {
        switch card.suit {
        case .hearts, .diamonds: return Color(red: 0.72, green: 0.13, blue: 0.16)
        case .spades, .clubs: return Color(red: 0.11, green: 0.12, blue: 0.14)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.09)
                .fill(.white)
            RoundedRectangle(cornerRadius: width * 0.09)
                .strokeBorder(.black.opacity(0.18), lineWidth: max(1, width * 0.012))

            VStack {
                corner
                Spacer(minLength: 0)
                corner.rotationEffect(.degrees(180))
            }
            .padding(width * 0.07)

            Text(card.suit.symbol)
                .font(.system(size: width * 0.46, weight: .regular))
                .foregroundStyle(colour)
        }
        .foregroundStyle(colour)
    }

    /// Rank over suit, in the top-left corner — the bottom-right is the same
    /// thing turned round, as on a real card.
    private var corner: some View {
        HStack {
            VStack(spacing: -width * 0.03) {
                Text(card.rank.label)
                    .font(.system(size: width * 0.26, weight: .bold, design: .rounded))
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.18))
            }
            Spacer(minLength: 0)
        }
    }
}

/// A card back drawn from scratch, for when even `back_red` is missing.
struct DrawnCardBack: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.09)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.11, blue: 0.14), Color(red: 0.33, green: 0.06, blue: 0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: width * 0.09)
                .strokeBorder(.white.opacity(0.65), lineWidth: max(1, width * 0.03))
                .padding(width * 0.07)
        }
    }
}

#Preview {
    HStack {
        CardView(card: Card(.ace, .spades))
        CardView(card: Card(.ten, .hearts))
        CardView(card: Card(.three, .clubs))
        CardView(card: nil, faceUp: false)
    }
    .padding()
    .background(.green.opacity(0.4))
}
