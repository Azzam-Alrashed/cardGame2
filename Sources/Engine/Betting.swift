import Foundation

/// A span of legal bets: every multiple of `increment` from `minimum` through
/// `maximum`.
///
/// This is a range rather than an array on purpose. A player may bet any
/// affordable multiple of 500, so a large stack has hundreds of legal bets, and
/// materialising `balance / 500` integers just to check whether one amount is
/// legal does not scale. `contains` is arithmetic; `options` is for feeding a
/// picker and is capped.
public struct BetRange: Hashable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let increment: Int

    public init(minimum: Int, maximum: Int, increment: Int = GameRules.betUnit) {
        self.minimum = minimum
        self.maximum = maximum
        self.increment = increment
    }

    public static let empty = BetRange(minimum: 0, maximum: -1)

    public var isEmpty: Bool { minimum > maximum }

    /// How many legal bets the range holds.
    public var count: Int {
        isEmpty ? 0 : (maximum - minimum) / increment + 1
    }

    public func contains(_ amount: Int) -> Bool {
        !isEmpty
            && amount >= minimum
            && amount <= maximum
            && (amount - minimum) % increment == 0
    }

    /// The bet at `index`, counting up from `minimum`.
    public func amount(at index: Int) -> Int? {
        guard index >= 0, index < count else { return nil }
        return minimum + index * increment
    }

    /// The largest legal bet not above `ceiling`, or `minimum` when even that
    /// is out of reach.
    public func largest(upTo ceiling: Int) -> Int {
        guard !isEmpty else { return 0 }
        guard ceiling >= minimum else { return minimum }
        return minimum + (min(ceiling, maximum) - minimum) / increment * increment
    }

    /// How far into the range to bet, from 0 at `minimum` to 1 at `maximum`.
    /// Useful for sizing a bet by appetite.
    public func amount(atFraction fraction: Double) -> Int {
        guard !isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return minimum + Int((Double(count - 1) * clamped).rounded()) * increment
    }

    /// Every legal bet, lowest first — for pickers and tests.
    ///
    /// Capped at `limit` entries so a very large stack cannot be turned into a
    /// very large array by accident. Use `contains` to validate and
    /// `amount(at:)` to index; reach for this only when you need the list.
    public func options(limit: Int = 120) -> [Int] {
        guard !isEmpty else { return [] }
        return (0..<min(count, limit)).map { minimum + $0 * increment }
    }
}

/// What a player may do on their turn.
public enum BetAction: Hashable, Sendable {
    /// Leave the round. Nothing is committed, nothing is lost, cards stay
    /// hidden (SPEC.md §10).
    case fold
    /// Commit this amount: any affordable multiple of 500, from 500 up.
    /// Nobody else's bet constrains it.
    case bet(Int)
    /// Commit the whole remaining balance — including a balance that is not a
    /// multiple of 500, which no ordinary bet can be (SPEC.md §9).
    case allIn
}

/// What a bet costs, and whether it is legal.
///
/// Betting is a single pass: in turn order every player folds once or commits
/// one amount, and when the last player has acted the amounts are final. That
/// is why players reach a showdown holding unequal bets, as SPEC.md §11's
/// worked example does, and it is why folding costs nothing — a fold happens
/// before any money is committed.
///
/// Two things this deliberately does **not** do:
///
/// - **No matching requirement.** What anyone else has bet does not constrain
///   what this player may bet. The minimum is 500 whatever is on the table, so
///   a player may enter for 500 against a standing bet of 10,000 and take that
///   hand to the showdown.
/// - **No step limit.** 500 is the increment, not a ladder. Any affordable
///   multiple of 500 is legal, so a 10,000 bet needs nothing but 10,000 in the
///   bank, and nothing caps a bet by the number of players.
public enum BettingRules {

    /// Whether `amount` is a well-formed bet: at least the minimum, and a
    /// whole number of 500s. Rejects 1,100, 1,750 and 2,300.
    public static func isWellFormed(_ amount: Int) -> Bool {
        amount >= GameRules.minimumBet && amount % GameRules.betUnit == 0
    }

    /// Every ordinary bet this player can make: 500 up to the largest multiple
    /// of 500 they can afford. Empty when they hold less than 500, which
    /// leaves them an all-in and a fold.
    public static func range(balance: Int) -> BetRange {
        let maximum = balance / GameRules.betUnit * GameRules.betUnit
        guard maximum >= GameRules.minimumBet else { return .empty }
        return BetRange(minimum: GameRules.minimumBet, maximum: maximum, increment: GameRules.betUnit)
    }

    /// Whether the player can make an ordinary bet at all.
    public static func canBet(balance: Int) -> Bool {
        !range(balance: balance).isEmpty
    }

    /// The smallest bet that enters the round, or nil when only an all-in or a
    /// fold is left.
    public static func cheapestBet(balance: Int) -> Int? {
        let span = range(balance: balance)
        return span.isEmpty ? nil : span.minimum
    }

    /// Whether a bare amount is a legal commitment.
    ///
    /// Every multiple of 500 from 500 up to what the player can afford, plus
    /// their whole balance as an all-in — the one amount exempt from the 500
    /// rule, since a balance need not be a multiple of 500 (a tie remainder can
    /// leave an odd one).
    public static func isLegal(amount: Int, balance: Int) -> Bool {
        if amount > 0, amount == balance { return true }
        return range(balance: balance).contains(amount)
    }

    /// What `action` costs this player, or nil when they cannot take it.
    public static func cost(of action: BetAction, balance: Int) -> Int? {
        switch action {
        case .fold:
            return 0
        case .bet(let amount):
            return isLegal(amount: amount, balance: balance) ? amount : nil
        case .allIn:
            return balance > 0 ? balance : nil
        }
    }

    public static func isLegal(_ action: BetAction, balance: Int) -> Bool {
        cost(of: action, balance: balance) != nil
    }

    /// Amounts a picker should offer: every legal bet up to `limit` of them,
    /// with the all-in added when it is not already one.
    public static func legalAmounts(balance: Int, limit: Int = 120) -> [Int] {
        var amounts = range(balance: balance).options(limit: limit)
        if balance > 0, !amounts.contains(balance) { amounts.append(balance) }
        return amounts.sorted()
    }

    /// Whether committing `amount` puts the player's whole balance on the round.
    public static func isAllIn(amount: Int, balance: Int) -> Bool {
        amount > 0 && amount == balance
    }
}
