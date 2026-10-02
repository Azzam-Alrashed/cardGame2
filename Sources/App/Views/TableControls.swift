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
                PrimaryButton(title: "Deal", systemImage: "play.fill") {
                    Task { await model.startRound() }
                }

            case .choosingAction:
                HStack(spacing: 12) {
                    PrimaryButton(title: "Enter round", systemImage: "arrow.down.circle.fill") {
                        model.chooseToEnterRound()
                    }
                    SecondaryButton(title: "Withdraw", systemImage: "xmark.circle") {
                        Task { await model.withdrawFromRound() }
                    }
                }

            case .pickingBet:
                StakePicker(
                    range: model.humanBetRange,
                    prompt: "Bet",
                    cancelTitle: "Back",
                    onCancel: { model.cancelBetPicker() },
                    onPick: { amount in Task { await model.placeBet(amount) } }
                )

            case .offeringToWithdraw:
                StakePicker(
                    range: model.humanOfferRange,
                    prompt: "Offer to withdraw",
                    cancelTitle: "Stay in",
                    onCancel: { Task { await model.declineToOffer() } },
                    onPick: { amount in Task { await model.sendOffer(amount) } }
                )

            case .resolvingOffers:
                OfferDecisions(model: model)

            case .roundOver:
                RoundSummary(model: model)

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

    /// The human's own name and coins. They get no seat badge — the control
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
                Text(player.coins, format: .number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// A horizontal run of legal stakes. Replaces the old `UIPickerView`: in
/// landscape a row reads better than a wheel, and the ends of the range are
/// one tap away.
struct StakePicker: View {
    let range: StakeRange
    let prompt: String
    let cancelTitle: String
    let onCancel: () -> Void
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(prompt)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(cancelTitle, action: onCancel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(range.options(limit: 60), id: \.self) { amount in
                        Button {
                            onPick(amount)
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

                    // The range can run long; offer the top of it directly.
                    if range.count > 60, let maximum = range.stake(at: range.count - 1) {
                        Button {
                            onPick(maximum)
                        } label: {
                            Label("All in \(maximum)", systemImage: "flame.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.orange.gradient, in: .capsule)
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
}

/// The top bettor's call on each offer, and the button that ends the round.
struct OfferDecisions: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 8) {
            if model.offersAwaitingHuman.isEmpty {
                Text("No offers — you hold the top bet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(model.offersAwaitingHuman) { offer in
                    OfferRow(offer: offer, senderName: model.engine.players[offer.sender]?.name ?? "—") { resolution in
                        model.resolve(offer, as: resolution)
                    }
                }
            }

            PrimaryButton(title: "Show cards", systemImage: "eye.fill") {
                Task { await model.endRound() }
            }
        }
    }
}

struct OfferRow: View {
    let offer: Offer
    let senderName: String
    let onResolve: (Offer.Resolution) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(senderName)
                .font(.system(size: 13, weight: .semibold))
            Text(offer.coins, format: .number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.yellow)

            Spacer(minLength: 8)

            if let resolution = offer.resolution {
                Text(resolution == .accepted ? "Accepted" : "Rejected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(resolution == .accepted ? .green : .red)
            } else {
                Button { onResolve(.accepted) } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                Button { onResolve(.rejected) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.white.opacity(0.1), in: .capsule)
        .frame(maxWidth: 360)
    }
}

struct RoundSummary: View {
    let model: GameTableViewModel

    var body: some View {
        VStack(spacing: 8) {
            if let outcome = model.outcome {
                if let winner = model.winnerName {
                    Text("\(winner) wins \(outcome.coinChanges[outcome.winner!] ?? 0)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text("Nobody entered the round")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            PrimaryButton(title: "Next round", systemImage: "arrow.clockwise") {
                Task { await model.startRound() }
            }
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
        case .betting(let seat):
            return "\(model.player(at: seat)?.name ?? seat.label) is deciding…"
        case .negotiation:
            return "Negotiating…"
        case .reveal:
            return "Scoring…"
        case .idle:
            return "Shuffling…"
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
