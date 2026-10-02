import SwiftUI

/// The table: four seats round the edges, the deck in the middle, the human's
/// controls at the bottom and the radial dial in the corner.
struct GameTableView: View {
    @State private var model = GameTableViewModel()

    var body: some View {
        ZStack {
            background

            // Everything else honours the safe area, so no seat ends up under
            // the notch or the home indicator.
            GeometryReader { geometry in
                ZStack {
                    deck(in: geometry.size)

                    ForEach(Seat.allCases, id: \.self) { seat in
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
            seat: seat,
            hand: model.hand(at: seat),
            dealtCards: model.dealtCards[seat] ?? 0,
            faceUp: model.showsFaces(at: seat),
            hasFolded: model.foldedSeats.contains(seat),
            cardWidth: cardWidth
        )
        .position(handPosition(seat, in: size, cardWidth: cardWidth))

        if let player = model.player(at: seat), seat != model.humanSeat {
            PlayerBadgeView(
                player: player,
                isActive: model.isTurn(of: seat),
                hasTopBet: model.isTopBettor(seat)
            )
            .position(badgePosition(seat, in: size))
        }

        if let bet = model.bubbles[seat] {
            BetBubbleView(seat: seat, amount: bet)
                .position(bubblePosition(seat, in: size))
        }
    }

    /// Landscape leaves about 400pt of height, so the controls take the
    /// bottom-trailing corner rather than the full width — otherwise they sit
    /// on top of the human's own cards.
    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                TableControls(model: model)
                    .frame(maxWidth: 360)
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

    // MARK: - Geometry
    //
    // Seats sit just inside their own edge. The human's hand is pulled a
    // little further in so the controls do not cover it.

    /// Hands hug their own edge. The human's sits left of centre so the
    /// controls in the opposite corner never cover it.
    private func handPosition(_ seat: Seat, in size: CGSize, cardWidth: CGFloat) -> CGPoint {
        let edge = cardWidth * 0.72
        switch seat {
        // A little further in, so the fan's corners clear the bottom edge.
        case .south: return CGPoint(x: size.width * 0.43, y: size.height - cardWidth * 0.95)
        case .north: return CGPoint(x: size.width / 2, y: edge + 8)
        case .east: return CGPoint(x: size.width - edge, y: size.height / 2)
        case .west: return CGPoint(x: edge, y: size.height / 2)
        }
    }

    /// Each badge sits on the table-centre side of its own cards. The human
    /// has none — their purse rides in the control bar instead.
    private func badgePosition(_ seat: Seat, in size: CGSize) -> CGPoint {
        switch seat {
        case .south: return CGPoint(x: size.width / 2, y: size.height - 24)
        case .north: return CGPoint(x: size.width / 2, y: 124)
        case .east: return CGPoint(x: size.width - 150, y: size.height / 2)
        case .west: return CGPoint(x: 150, y: size.height / 2)
        }
    }

    /// Bubbles sit beside their seat, clear of the badges.
    private func bubblePosition(_ seat: Seat, in size: CGSize) -> CGPoint {
        switch seat {
        case .south: return CGPoint(x: size.width * 0.43 - 180, y: size.height - 96)
        case .north: return CGPoint(x: size.width / 2 + 190, y: 56)
        case .east: return CGPoint(x: size.width - 150, y: size.height / 2 - 88)
        case .west: return CGPoint(x: 150, y: size.height / 2 - 88)
        }
    }
}

#Preview(traits: .landscapeLeft) {
    GameTableView()
}
