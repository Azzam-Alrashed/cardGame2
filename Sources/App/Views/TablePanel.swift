import SwiftUI

/// The sliding panel the radial dial opens, over the table.
struct TablePanel: View {
    let panel: GameTableViewModel.Panel
    let model: GameTableViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.15))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 320)
        .background(.black.opacity(0.72))
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 20, x: -6)
    }

    private var header: some View {
        HStack {
            Text(panel.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .offers: offers
        case .leaderboard: leaderboard
        case .info: info
        }
    }

    private var offers: some View {
        ScrollView {
            VStack(spacing: 8) {
                if model.engine.offers.isEmpty {
                    emptyNote("No Sharah offers this round")
                } else {
                    ForEach(model.engine.offers) { offer in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(name(offer.from))
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(name(offer.to))
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(offer.amount, format: .number)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            Text(offer.state.rawValue.capitalized)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(color(for: offer.state))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .padding(14)
        }
    }

    private func name(_ id: PlayerID) -> String {
        model.engine.players[id]?.name ?? "—"
    }

    private var leaderboard: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(model.engine.leaderboard.enumerated()), id: \.element.id) { rank, player in
                    HStack(spacing: 10) {
                        crown(for: rank)
                        Image(player.avatarName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(.circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(player.seat.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text(player.balance, format: .number)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        player.seat == model.humanSeat ? .white.opacity(0.14) : .white.opacity(0.06),
                        in: .rect(cornerRadius: 10)
                    )
                }
            }
            .padding(14)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("State", model.engine.phase.name)
            row("Round", "\(model.engine.roundIndex + 1)")
            row("Leads", model.engine.turnOrder.first.map(name) ?? "—")
            row("Highest bet", model.engine.highestBet == 0 ? "—" : model.engine.highestBet.formatted())
            row("Minimum bet", GameRules.minimumBet.formatted())
            row("Target", GameRules.targetBalance.formatted())
            row("Undealt cards", "\(model.engine.undealtCards)")
            row("Tiebreak", "Rank only — ties split")

            if let hand = model.hand(at: model.humanSeat) {
                Divider().overlay(.white.opacity(0.15))
                Text("Your hand")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(hand.description)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(hand.ranking.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.vertical, 24)
    }

    /// The original crown art, best rank first.
    @ViewBuilder
    private func crown(for rank: Int) -> some View {
        let crowns = ["Crown0", "Crown1", "Crown2", "Crown4"]
        if rank < crowns.count {
            Image(crowns[rank])
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else {
            Text("\(rank + 1)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22)
        }
    }

    private func color(for state: SharahOffer.State) -> Color {
        switch state {
        case .accepted: return .green
        case .rejected: return .red
        case .pending: return .yellow
        }
    }
}
