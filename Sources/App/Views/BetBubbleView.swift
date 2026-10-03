import SwiftUI

/// A seat's bet, in the speech bubble the original art was drawn for.
struct BetBubbleView: View {
    let amount: Int
    /// Art that points toward the seat it belongs to.
    let imageName: String

    var body: some View {
        Text(amount, format: .number)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Image(imageName)
                    .resizable(capInsets: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }
}

/// The player's avatar, name and balance.
struct PlayerBadgeView: View {
    let player: Player
    var isActive: Bool = false
    var hasTopBet: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(player.avatarName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(isActive ? .yellow : .white.opacity(0.35), lineWidth: isActive ? 2.5 : 1)
                }
                .grayscale(player.isEliminated ? 1 : 0)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(player.name)
                        .font(.system(size: 13, weight: .semibold))
                    if hasTopBet {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
                Text(player.isEliminated ? "Out" : player.balance.formatted())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: .capsule)
        .overlay {
            Capsule().strokeBorder(.white.opacity(isActive ? 0.5 : 0.12), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
