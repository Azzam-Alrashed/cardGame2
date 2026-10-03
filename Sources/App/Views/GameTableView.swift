import SwiftUI

/// The table: seats round the edges, the deck in the middle, the human's
/// controls at the bottom and the radial dial in the corner.
struct GameTableView: View {
    @State private var model = GameTableViewModel()

    private var layout: TableLayout {
        TableLayout(seats: model.seats, humanSeat: model.humanSeat)
    }

    var body: some View {
        ZStack {
            background

            // Everything else honours the safe area, so no seat ends up under
            // the notch or the home indicator.
            GeometryReader { geometry in
                ZStack {
                    deck(in: geometry.size)

                    ForEach(model.seats) { seat in
                        seatLayer(seat, in: geometry.size)
                    }

                    controls

                    dial

                    panel
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Layers

    /// The table felt, edge to edge. `scaledToFill` is clipped by the frame it
    /// is given: left to size itself, the image expands to its own pixel
    /// dimensions and drags everything stacked with it off-screen.
    private var background: some View {
        GeometryReader { geometry in
            Image("background-2")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(.black.opacity(0.3))
        }
        .ignoresSafeArea()
    }

    private func deck(in size: CGSize) -> some View {
        CardView(card: nil, faceUp: false, width: 54)
            .rotationEffect(.degrees(-8))
            .opacity(0.9)
            .position(x: size.width / 2, y: size.height / 2)
    }

    /// A seat's cards, badge and bet bubble, placed along its own edge.
    @ViewBuilder
    private func seatLayer(_ seat: Seat, in size: CGSize) -> some View {
        let isHuman = seat == model.humanSeat
        let cardWidth: CGFloat = isHuman ? 76 : 52

        SeatHandView(
            hand: model.hand(at: seat),
            dealtCards: model.dealtCards[seat] ?? 0,
            faceUp: model.showsFaces(at: seat),
            hasFolded: model.foldedSeats.contains(seat),
            rotation: layout.cardRotation(of: seat),
            dealEdge: layout.dealEdge(of: seat),
            cardWidth: cardWidth
        )
        .position(handPosition(seat, in: size, cardWidth: cardWidth))

        if let player = model.player(at: seat), !isHuman {
            PlayerBadgeView(
                player: player,
                isActive: model.isTurn(of: seat),
                hasTopBet: model.isTopBettor(seat)
            )
            .position(layout.position(of: seat, in: size, inset: 96, pull: 0.74))
        }

        if let bet = model.bubbles[seat] {
            BetBubbleView(amount: bet, imageName: layout.bubbleImageName(of: seat))
                .position(layout.position(of: seat, in: size, inset: 96, pull: 0.44))
        }
    }

    /// The near seat's fan is held clear of the control bar; every other seat
    /// sits on the table's ellipse.
    private func handPosition(_ seat: Seat, in size: CGSize, cardWidth: CGFloat) -> CGPoint {
        guard seat == model.humanSeat else {
            return layout.position(of: seat, in: size, inset: cardWidth * 0.9)
        }
        return layout.nearSeatPosition(
            in: size,
            cardWidth: cardWidth,
            reservedTrailingWidth: Self.controlsWidth + 16
        )
    }

    /// Matches the frame the control bar is given below.
    private static let controlsWidth: CGFloat = 400

    /// Landscape leaves about 400pt of height, so the controls take the
    /// bottom-trailing corner rather than the full width — otherwise they sit
    /// on top of the human's own cards.
    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                TableControls(model: model)
                    .frame(maxWidth: Self.controlsWidth)
            }
        }
    }

    private var dial: some View {
        VStack {
            Spacer()
            HStack {
                RadialNavButton(selection: $model.openPanel)
                Spacer()
            }
        }
        .padding(.leading, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var panel: some View {
        if let open = model.openPanel {
            HStack {
                Spacer()
                TablePanel(panel: open, model: model) {
                    model.openPanel = nil
                }
                .padding(.vertical, 6)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.openPanel)
        }
    }
}

#Preview(traits: .landscapeLeft) {
    GameTableView()
}
