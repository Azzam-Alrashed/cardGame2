import Foundation

/// How a round's money moves (SPEC.md §7).
public struct SettlementLedger: Hashable, Sendable {
    /// Tied winners, in turn order. Empty when nobody reached the showdown.
    public let winners: [PlayerID]
    /// The largest amount any player committed this round.
    public let highestBet: Int
    /// What each winner collects. A split, when there is more than one.
    public let rewards: [PlayerID: Int]
    /// What each losing player pays: their own bet, exactly.
    public let losses: [PlayerID: Int]
    /// Rewards and losses together, as a signed change per player.
    public let netChange: [PlayerID: Int]

    public static let empty = SettlementLedger(
        winners: [], highestBet: 0, rewards: [:], losses: [:], netChange: [:]
    )

    public init(
        winners: [PlayerID],
        highestBet: Int,
        rewards: [PlayerID: Int],
        losses: [PlayerID: Int],
        netChange: [PlayerID: Int]
    ) {
        self.winners = winners
        self.highestBet = highestBet
        self.rewards = rewards
        self.losses = losses
        self.netChange = netChange
    }
}

/// Settles a round.
///
/// There is no pot. The winner's reward and each loser's loss are independent
/// quantities, and neither is derived from the other: the winner collects the
/// round's highest bet whoever placed it, and every losing player pays exactly
/// what they themselves bet. The losers' bets are never summed.
///
/// A consequence, recorded in SPEC.md §9: the money supply is not conserved.
/// It shrinks at a crowded table and grows when a big bettor wins heads-up.
/// That is the rule as specified, not a bug in this function.
public enum Settlement {

    /// - Parameters:
    ///   - showdown: the players who reached the showdown, in turn order, with
    ///     their hands. Folded and bought-out players are not here.
    ///   - bets: every bet committed this round, by player. Includes players
    ///     who later left via Sharah — their bet still counts toward the
    ///     round's highest bet, and buying out the top bettor does not shrink
    ///     the prize.
    public static func settle(
        showdown: [(id: PlayerID, hand: Hand)],
        bets: [PlayerID: Int]
    ) -> SettlementLedger {
        let highestBet = bets.values.max() ?? 0
        let winners = HandComparator.strongest(among: showdown)
        guard !winners.isEmpty else { return .empty }

        // Tied winners split the highest bet with integer division; the
        // remainder goes to whichever of them comes first in turn order, which
        // is the order `showdown` was given in (SPEC.md §7).
        var rewards: [PlayerID: Int] = [:]
        let share = highestBet / winners.count
        let remainder = highestBet % winners.count
        for (offset, winner) in winners.enumerated() {
            rewards[winner] = share + (offset == 0 ? remainder : 0)
        }

        // Everyone else at the showdown pays their own bet and nothing more.
        var losses: [PlayerID: Int] = [:]
        for (id, _) in showdown where rewards[id] == nil {
            losses[id] = bets[id] ?? 0
        }

        var netChange: [PlayerID: Int] = [:]
        for (id, reward) in rewards { netChange[id, default: 0] += reward }
        for (id, loss) in losses { netChange[id, default: 0] -= loss }

        return SettlementLedger(
            winners: winners,
            highestBet: highestBet,
            rewards: rewards,
            losses: losses,
            netChange: netChange
        )
    }

    /// Players who are out of the game (SPEC.md §8).
    ///
    /// Any balance of zero at the end of a round's settlement eliminates. Note
    /// what this is *not*: being unable to match the biggest bet is not
    /// elimination — a player with money always has a legal bet, and a player
    /// with almost none always has an all-in.
    public static func eliminated(among players: [Player]) -> [PlayerID] {
        players.filter { !$0.isEliminated && $0.balance <= 0 }.map(\.id)
    }

    /// The player who has won the game, if any (SPEC.md §13).
    ///
    /// Either of two ways: reaching the target, or being the only player left.
    ///
    /// A tie split can carry two players over the target in the same
    /// settlement. The larger final balance takes it; an exact draw goes to
    /// whoever comes first in the current turn order.
    public static func gameWinner(among players: [Player], turnOrder: [PlayerID]) -> PlayerID? {
        let position = Dictionary(uniqueKeysWithValues: turnOrder.enumerated().map { ($1, $0) })
        let reached = players.filter(\.hasReachedTarget)

        if !reached.isEmpty {
            return reached.min { lhs, rhs in
                lhs.balance != rhs.balance
                    ? lhs.balance > rhs.balance
                    : (position[lhs.id] ?? .max) < (position[rhs.id] ?? .max)
            }?.id
        }

        return lastPlayerStanding(among: players)
    }

    /// The only player with anything left, when everyone else has been
    /// eliminated (SPEC.md §13).
    public static func lastPlayerStanding(among players: [Player]) -> PlayerID? {
        let survivors = players.filter(\.isActive)
        return survivors.count == 1 ? survivors[0].id : nil
    }
}
