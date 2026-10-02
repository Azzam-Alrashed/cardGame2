import SwiftUI

/// One playing card, face up or face down, at the deck's 2:3 proportions.
struct CardView: View {
    let card: Card?
    var faceUp: Bool = true
    var width: CGFloat = 76

    /// The proportions the original art was drawn at.
    static let aspectRatio: CGFloat = 2 / 3

    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: width / Self.aspectRatio)
            .clipShape(.rect(cornerRadius: width * 0.09))
            .shadow(color: .black.opacity(0.35), radius: width * 0.05, y: width * 0.03)
    }

    private var imageName: String {
        guard faceUp, let card else { return "back_red" }
        return card.imageName
    }
}

#Preview {
    HStack {
        CardView(card: Card(.ace, .spades))
        CardView(card: Card(.queen, .hearts))
        CardView(card: nil, faceUp: false)
    }
    .padding()
    .background(.green.opacity(0.4))
}
