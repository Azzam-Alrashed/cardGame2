import SwiftUI

/// Where the dial's destinations sit and which one a finger has landed on.
///
/// This is the part of the control worth testing, so it lives outside the
/// view: given a drag translation it answers which destination would be
/// picked, with no gesture or simulator involved.
struct RadialDial<Destination: Equatable> {
    let destinations: [Destination]
    /// How far the destinations sit from the dot.
    var radius: CGFloat = 84
    /// How close a finger must be to a destination to pick it.
    var hitRadius: CGFloat = 38
    /// Destinations fan over this arc, measured from straight up.
    var sweep: Double = .pi / 2

    /// Where `destination` sits relative to the dot. The fan opens up and to
    /// the right, because the dot lives in the bottom-left corner.
    func offset(for destination: Destination) -> CGSize {
        guard let index = destinations.firstIndex(of: destination) else { return .zero }
        guard destinations.count > 1 else { return CGSize(width: 0, height: -radius) }
        let step = sweep / Double(destinations.count - 1)
        let angle = -Double.pi / 2 + Double(index) * step
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }

    /// The destination a finger at `translation` would pick, or nil if it is
    /// not close enough to any of them.
    func destination(nearest translation: CGSize) -> Destination? {
        destinations
            .map { ($0, distance(translation, offset(for: $0))) }
            .filter { $0.1 <= hitRadius }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    private func distance(_ a: CGSize, _ b: CGSize) -> CGFloat {
        let dx = a.width - b.width
        let dy = a.height - b.height
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The home button from the original: a dot that blooms into a dial when you
/// press and drag, with three destinations you drop onto.
///
/// The old version tracked a `UIPanGestureRecognizer` against a finger-tracker
/// view and hit-tested `frame.intersects` on three image views. This keeps the
/// feel — press, bloom, drag, release on a target — with the geometry in one
/// place and a plain tap as a shortcut.
struct RadialNavButton: View {
    @Binding var selection: GameTableViewModel.Panel?

    @State private var isOpen = false
    @State private var isDragging = false
    @State private var fingerOffset: CGSize = .zero
    @State private var highlighted: GameTableViewModel.Panel?

    private let dial_ = RadialDial(destinations: GameTableViewModel.Panel.allCases)
    private var destinations: [GameTableViewModel.Panel] { dial_.destinations }
    private var dialRadius: CGFloat { dial_.radius }

    var body: some View {
        ZStack {
            dial
            fingerTracker
            dot
        }
        .frame(width: 60, height: 60)
        .gesture(drag)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isOpen)
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }

    // MARK: - Pieces

    private var dot: some View {
        Button {
            if selection != nil {
                selection = nil
            } else {
                isOpen.toggle()
            }
        } label: {
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1)
                }
                .shadow(radius: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selection == nil ? "Open menu" : "Close panel")
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(isOpen ? 0.35 : 0))
                .frame(width: isOpen ? dialRadius * 2.2 : 20)

            ForEach(destinations) { panel in
                destinationIcon(panel)
                    .offset(offset(for: panel))
                    .opacity(isOpen ? 1 : 0)
                    .scaleEffect(isOpen ? (highlighted == panel ? 1.25 : 1) : 0.4)
            }
        }
        // While a drag is in flight the destinations must not take the touch:
        // a Button that accepts it cancels the parent drag, so `onEnded` never
        // runs and the drop is lost. They become tappable once the finger is
        // up and the dial is simply sitting open.
        .allowsHitTesting(isOpen && !isDragging)
    }

    private func destinationIcon(_ panel: GameTableViewModel.Panel) -> some View {
        Button {
            selection = panel
            close()
        } label: {
            Image(panel.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .padding(10)
                .background(.black.opacity(highlighted == panel ? 0.75 : 0.45), in: .circle)
                .overlay {
                    Circle().strokeBorder(.white.opacity(highlighted == panel ? 0.9 : 0.2), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.title)
    }

    /// Mirrors the finger while the dial is open, as the old tracker view did.
    private var fingerTracker: some View {
        Circle()
            .fill(.white.opacity(0.5))
            .frame(width: 26, height: 26)
            .offset(fingerOffset)
            .opacity(isOpen && fingerOffset != .zero ? 0.7 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                isOpen = true
                isDragging = true
                fingerOffset = value.translation
                highlighted = destination(nearest: value.translation)
            }
            .onEnded { value in
                if let landed = destination(nearest: value.translation) {
                    selection = landed
                    close()
                } else {
                    // Released on nothing: leave the dial open so the
                    // destinations can be tapped instead.
                    isDragging = false
                    fingerOffset = .zero
                    highlighted = nil
                }
            }
    }

    private func close() {
        isOpen = false
        isDragging = false
        fingerOffset = .zero
        highlighted = nil
    }

    private func destination(nearest translation: CGSize) -> GameTableViewModel.Panel? {
        dial_.destination(nearest: translation)
    }

    private func offset(for panel: GameTableViewModel.Panel) -> CGSize {
        dial_.offset(for: panel)
    }
}

extension GameTableViewModel.Panel {
    var title: String {
        switch self {
        case .offers: return "Offers"
        case .leaderboard: return "Players"
        case .info: return "Round"
        }
    }

    var iconName: String {
        switch self {
        case .offers: return "offersView-w"
        case .leaderboard: return "playersView-w"
        case .info: return "settings-w"
        }
    }
}
