import SwiftUI

/// Everything the human is asked to do, in one bar at the bottom of the table.
/// What it shows follows the view model's `interaction`.
struct TableControls: View {
    @Bindable var model: GameTableViewModel

    var body: some View {
        VStack(spacing: 10) {
            purse

            if let message = model.message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .transition(.opacity)
            }

            switch model.interaction {
            case .readyToDeal:
                if model.canDeal {
                    PrimaryButton(title: "Deal", systemImage: "play.fill") {
                        Task { await model.startRound() }
                    }
                } else {
                    Text("Not enough players left to deal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

            case .choosingAction:
                BettingActions(model: model)

            case .offeringSharah:
                SharahOfferPicker(model: model)

            case .respondingToSharah(let offer):
                SharahResponse(model: model, offer: offer)

            case .roundOver:
                RoundSummary(model: model)

            case .gameOver:
                GameSummary(model: model)

            case .watching:
                WaitingIndicator(model: model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.4), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: model.interaction)
    }

    /// The human's own name and balance. They get no seat badge — the control
    /// bar already occupies their edge of the table.
    @ViewBuilder
    private var purse: some View {
        if let player = model.human {
            HStack(spacing: 6) {
                Text(player.name)
                    .font(.system(size: 12, weight: .semibold))
                if model.isTopBettor(model.humanSeat) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(player.balance, format: .number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Fold, bet any affordable multiple of 500, or go all-in (SPEC.md §9).
///
/// The range can run to hundreds of bets on a large stack, so the row shows
/// the cheapest ones and the all-in button covers the top of it.
struct BettingActions: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text(prompt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("Fold", style: AnyShapeStyle(.white.opacity(0.14)), tint: .white) {
                        Task { await model.take(.fold) }
                    }

                    ForEach(model.humanBetOptions, id: \.self) { amount in
                        chip(amount.formatted(), style: AnyShapeStyle(.white.opacity(0.92)), tint: .black) {
                            Task { await model.take(.bet(amount)) }
                        }
                    }

                    if let allIn = model.humanAllIn {
                        chip("All in \(allIn.formatted())", style: AnyShapeStyle(Color.orange.gradient), tint: .white) {
                            Task { await model.take(.allIn) }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 460)
        }
    }

    private var prompt: String {
        let range = model.humanBetRange
        if range.isEmpty {
            return "Under 500 left — fold or go all-in"
        }
        guard model.engine.highestBet > 0 else {
            return "Open the round — \(range.minimum.formatted()) or more"
        }
        // The biggest bet is public, and it is a claim rather than a price:
        // nothing stops this player entering for the minimum.
        return "Biggest bet \(model.engine.highestBet.formatted()) — bet \(range.minimum.formatted()) or more"
    }

    private func chip(
        _ title: String,
        style: AnyShapeStyle,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(style, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Offering a rival money to leave the round.
struct SharahOfferPicker: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(target.map { "Pay \($0.name) to leave?" } ?? "Sharah")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Stay in") {
                    Task { await model.declineToOfferSharah() }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.humanSharahAmounts, id: \.self) { amount in
                        Button {
                            Task { await model.offerSharah(amount) }
                        } label: {
                            Text(amount, format: .number)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.92), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 440)
        }
    }

    private var target: PublicPlayerView? { model.sharahTarget }
}

/// Someone has offered the human money to leave the round.
struct SharahResponse: View {
    let model: GameTableViewModel
    let offer: SharahOffer

    var body: some View {
        VStack(spacing: 8) {
            Text("\(senderName) offers \(offer.amount.formatted()) for you to leave")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Your bet of \(model.engine.bet(of: model.humanID ?? "").formatted()) is not lost either way")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 12) {
                PrimaryButton(title: "Take it", systemImage: "hand.thumbsup.fill") {
                    Task { await model.respond(to: offer, accept: true) }
                }
                SecondaryButton(title: "Refuse", systemImage: "xmark.circle") {
                    Task { await model.respond(to: offer, accept: false) }
                }
            }
        }
    }

    private var senderName: String {
        model.engine.players[offer.from]?.name ?? "Someone"
    }
}

struct RoundSummary: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 8) {
            if let result = model.result {
                if model.winnerNames.isEmpty {
                    Text("Nobody reached the showdown")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(headline(result))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                if !result.eliminated.isEmpty {
                    Text(eliminatedNames(result) + " out of the game")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            PrimaryButton(title: "Next round", systemImage: "arrow.clockwise") {
                Task { await model.startRound() }
            }
        }
    }

    /// The winner takes the round's highest bet, whoever placed it — split,
    /// when a true tie puts two hands level.
    private func headline(_ result: RoundResult) -> String {
        let names = model.winnerNames.formatted(.list(type: .and))
        guard let first = result.winners.first else { return names }
        let reward = result.reward(for: first)
        return result.winners.count == 1
            ? "\(names) wins \(reward.formatted())"
            : "\(names) tie and split \(result.highestBet.formatted())"
    }

    private func eliminatedNames(_ result: RoundResult) -> String {
        result.eliminated
            .compactMap { model.engine.players[$0]?.name }
            .formatted(.list(type: .and))
    }
}

struct GameSummary: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .foregroundStyle(.yellow)
            Text("\(model.gameWinnerName ?? "Someone") reaches \(GameRules.targetBalance.formatted())")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Game over")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct WaitingIndicator: View {
    let model: GameTableViewModel

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(height: 30)
    }

    private var caption: String {
        switch model.engine.phase {
        case .betting(let turn):
            return "\(model.engine.players[turn]?.name ?? "Someone") is deciding…"
        case .negotiation:
            return "Negotiating…"
        case .showdown, .settlement:
            return "Scoring…"
        case .dealing, .privateHands:
            return "Dealing…"
        case .waitingForPlayers, .roundOver:
            return "Shuffling…"
        case .gameOver:
            return "Game over"
        }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(0.94), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(0.14), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}
