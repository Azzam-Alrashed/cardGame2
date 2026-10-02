import Foundation

/// A span of legal stakes: every multiple of `increment` from `minimum`
/// through `maximum`.
///
/// This is a range rather than an array on purpose. A stack of a few thousand
/// coins only has a few dozen legal bets, but stacks grow, and materialising
/// `coins / increment` integers just to check whether one bet is legal does
/// not scale. `contains` is arithmetic; `options` is for feeding a picker and
/// is capped.
public struct StakeRange: Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let increment: Int

    public init(minimum: Int, maximum: Int, increment: Int = GameRules.betIncrement) {
        self.minimum = minimum
        self.maximum = maximum
        self.increment = increment
    }

    public static let empty = StakeRange(minimum: 0, maximum: -1)

    public var isEmpty: Bool { minimum > maximum }

    /// Number of legal stakes in the range.
    public var count: Int {
        isEmpty ? 0 : (maximum - minimum) / increment + 1
    }

    public func contains(_ amount: Int) -> Bool {
        !isEmpty
            && amount >= minimum
            && amount <= maximum
            && (amount - minimum) % increment == 0
    }

    /// The stake at `index`, counting up from `minimum`.
    public func stake(at index: Int) -> Int? {
        guard index >= 0, index < count else { return nil }
        return minimum + index * increment
    }

    /// The largest legal stake not above `ceiling`, or `minimum` when even
    /// that is out of reach.
    public func largestStake(upTo ceiling: Int) -> Int {
        guard !isEmpty else { return 0 }
        guard ceiling >= minimum else { return minimum }
        let steps = (min(ceiling, maximum) - minimum) / increment
        return minimum + steps * increment
    }

    /// How many increments into the range `amount` sits, from 0 at `minimum`
    /// to 1 at `maximum`. Useful for sizing a bet by confidence.
    public func stake(atFraction fraction: Double) -> Int {
        guard !isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let steps = Int((Double(count - 1) * clamped).rounded())
        return minimum + steps * increment
    }

    /// Every legal stake, lowest first — for pickers and tests.
    ///
    /// Capped at `limit` entries so a very large stack cannot be turned into a
    /// very large array by accident. Use `contains` to validate and
    /// `stake(at:)` to index; reach for this only when you need the list.
    public func options(limit: Int = 1000) -> [Int] {
        guard !isEmpty else { return [] }
        let n = min(count, limit)
        return (0..<n).map { minimum + $0 * increment }
    }
}

/// The game's tunable constants and rule variants, all in one place.
public enum GameRules {
    public static let startingCoins = 5000
    /// Every bet and offer is a multiple of this.
    public static let betIncrement = 100
    public static let handSize = 4
    public static let seatCount = 4

    /// How a round's coins move once the hands are scored.
    public enum Payout: Sendable {
        /// Losing entrants pay the bet they placed, and the winner collects
        /// exactly that — so the table's coin supply is constant.
        ///
        /// This matches the spec's own worked example (one player in for 100,
        /// another for 2000; the winner takes 2000) and is the default because
        /// it is the only variant that cannot run away.
        case conserving

        /// The original game's arithmetic: the winner gains the round's top
        /// bet and their own stake is never deducted.
        ///
        /// Coins are created on every win, so stacks compound — roughly 1.6×
        /// per win against the default AI — and a long session will overflow
        /// `Int`. Here for fidelity; not safe to leave running.
        case topBetToWinner
    }

    public static let defaultPayout = Payout.conserving

    /// Legal bets for a player holding `coins`, given the highest bet already
    /// placed this round.
    ///
    /// A player must raise by at least one increment over the standing bet —
    /// unless they cannot afford to, in which case they may still enter from
    /// the minimum. (That carve-out is the original game's rule; it lets a
    /// short-stacked player enter below the top bet rather than be shut out.)
    public static func betRange(coins: Int, highestBet: Int) -> StakeRange {
        let minimum = coins > highestBet ? highestBet + betIncrement : betIncrement
        guard coins >= minimum else { return .empty }
        let maximum = minimum + (coins - minimum) / betIncrement * betIncrement
        return StakeRange(minimum: minimum, maximum: maximum)
    }

    /// Legal offer amounts a withdrawing player may put to the top bettor.
    /// Offers are capped by the top bet and by what the offerer can pay.
    public static func offerRange(coins: Int, topBet: Int) -> StakeRange {
        let ceiling = min(coins, topBet)
        guard ceiling >= betIncrement else { return .empty }
        let maximum = ceiling / betIncrement * betIncrement
        return StakeRange(minimum: betIncrement, maximum: maximum)
    }

    /// Turn order for a round, starting with the player left of the dealer and
    /// rotating one seat per round.
    public static func turnOrder(round: Int) -> [Seat] {
        let seats = Seat.allCases
        let offset = round % seats.count
        return (0..<seats.count).map { seats[($0 + offset) % seats.count] }
    }
}
