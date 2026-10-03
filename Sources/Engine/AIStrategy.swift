import Foundation

/// An opponent that plays without seeing anyone else's cards.
///
/// The old AI sized its bet directly against its own hand, which made every
/// bet it placed an honest signal of strength and the whole table readable.
/// SPEC.md §10 forbids exactly that: a bet is a claim, not evidence. So this
/// version mixes hand strength with pressure, stack risk and a coin toss, and
/// deliberately does the wrong-looking thing some of the time — bluffs a
/// rainbow into a raise, and sometimes flat-matches four aces.
///
/// Its inputs are its own hand, its own balance and a `PublicTableView`, which
/// has `nil` for every opponent's hand until the showdown. There is no path
/// from here to a hidden card.
public struct AIStrategy: Sendable {

    public struct Personality: Hashable, Sendable {
        /// Below this willingness it folds rather than pay to stay in.
        public var foldThreshold: Double
        /// Chance of talking itself into a hand it should not play.
        public var bluffChance: Double
        /// Chance of underbetting a strong hand to keep it quiet.
        public var trapChance: Double
        /// How readily it raises rather than matches, 0...1.
        public var aggression: Double
        /// How much it fears committing a large share of its stack, 0...1.
        public var riskAversion: Double
        /// How readily it pays to remove a rival, or takes money to leave.
        public var sharahAppetite: Double
        /// Spread of the random noise added to every decision.
        public var noise: Double

        public init(
            foldThreshold: Double = 0.34,
            bluffChance: Double = 0.18,
            trapChance: Double = 0.2,
            aggression: Double = 0.5,
            riskAversion: Double = 0.5,
            sharahAppetite: Double = 0.4,
            noise: Double = 0.18
        ) {
            self.foldThreshold = foldThreshold
            self.bluffChance = bluffChance
            self.trapChance = trapChance
            self.aggression = aggression
            self.riskAversion = riskAversion
            self.sharahAppetite = sharahAppetite
            self.noise = noise
        }

        public static let cautious = Personality(
            foldThreshold: 0.45, bluffChance: 0.07, trapChance: 0.3,
            aggression: 0.25, riskAversion: 0.8, sharahAppetite: 0.6, noise: 0.12
        )
        public static let balanced = Personality()
        public static let reckless = Personality(
            foldThreshold: 0.2, bluffChance: 0.35, trapChance: 0.1,
            aggression: 0.8, riskAversion: 0.2, sharahAppetite: 0.25, noise: 0.25
        )
    }

    public var personality: Personality
    private var rng: RandomGenerator

    public init(personality: Personality = .balanced, seed: UInt64? = nil) {
        self.personality = personality
        self.rng = RandomGenerator(seed: seed)
    }

    /// A rough 0...1 reading of a hand, for the AI's own use.
    ///
    /// This is a heuristic for betting, **not** a hand score: nothing compares
    /// two hands with it. Showdowns go through `HandComparator`, which is the
    /// only authority (SPEC.md §6).
    public static func handStrength(_ hand: Hand) -> Double {
        let type = Double(hand.combination.rawValue)
        let top = Double((hand.orderedRanks.first ?? .two).strength - Rank.two.strength)
        let span = Double(Rank.ace.strength - Rank.two.strength)
        return (type + top / (span + 1)) / Double(Combination.fourOfAKind.rawValue + 1)
    }

    // MARK: - Betting

    /// What to do on this turn.
    ///
    /// Nobody's bet forces this one: the minimum is 500 whatever is on the
    /// table, so the question is only whether to play and for how much. Sizing
    /// is deliberately not a function of the hand — a bluff sizes up, a trap
    /// sizes down to the minimum, and noise moves both — so a large bet is no
    /// more readable than a small one.
    public mutating func decideBet(hand: Hand, balance: Int, table: PublicTableView) -> BetAction {
        guard balance > 0 else { return .fold }
        let span = BettingRules.range(balance: balance)

        let strength = Self.handStrength(hand)
        let bluffing = roll() < personality.bluffChance
        let trapping = strength >= 0.6 && roll() < personality.trapChance

        // Public behaviour, which is all there is to read: rivals still in
        // argue for caution, rivals who left argue the other way.
        let crowd = Double(table.opponentsInRound.count)
        let pressure = min(0.3, 0.06 * crowd) - min(0.2, 0.05 * Double(table.opponentsOut))

        // A bet far larger than this stack is a claim worth respecting even
        // though it costs nothing to enter under it — losing a showdown to it
        // is what elimination looks like.
        let exposure = min(1, Double(table.highestBet) / Double(balance))
        let fear = personality.riskAversion * exposure * 0.4

        var willingness = strength + (bluffing ? 0.45 : 0) - pressure - fear + jitter()
        if exposure >= 1 { willingness -= (1 - strength) * personality.riskAversion * 0.5 }

        guard willingness >= personality.foldThreshold else { return .fold }

        // Less than 500 left: all-in is the only way in, which SPEC.md §9
        // allows whatever anyone else has bet.
        guard !span.isEmpty else { return .allIn }

        // A trap keeps a strong hand quiet, so a small bet is no safer to read
        // than a large one.
        if trapping { return .bet(span.minimum) }

        // Shove when the claim is loud enough to be worth making outright.
        let shoveLine = 1.05 - 0.35 * personality.aggression
        if willingness >= shoveLine { return .allIn }

        // Otherwise pick a size: appetite times the share of the stack this
        // personality will put up, and a bluff reaches further.
        let appetite = min(1, max(0, willingness))
        let share = (0.08 + 0.5 * personality.aggression)
            * appetite
            * (bluffing ? 1.8 : 1)
            * (1 - 0.4 * personality.riskAversion)
        let ceiling = Int(Double(balance) * min(1, share))
        return .bet(span.largest(upTo: ceiling))
    }

    // MARK: - Sharah

    /// Who to pay to leave the round, and how much — or nil to leave it alone.
    ///
    /// Paying a rival out costs money now and removes a hand that might have
    /// beaten this one. Worth it with a decent hand and a crowded table; never
    /// worth it with nothing.
    public mutating func decideSharahOffer(
        hand: Hand,
        available: Int,
        table: PublicTableView
    ) -> (to: PlayerID, amount: Int)? {
        guard available > 0 else { return nil }
        let rivals = table.opponentsInRound
        guard !rivals.isEmpty else { return nil }

        let strength = Self.handStrength(hand)
        let appetite = personality.sharahAppetite * (0.35 + strength) + jitter()
        guard appetite > 0.5 else { return nil }

        // The biggest bettor is the loudest threat, which may be a bluff — the
        // point is that there is no way to tell, so loudness is what there is.
        let target = rivals.max { $0.bet < $1.bet } ?? rivals[0]
        let share = min(0.45, appetite * 0.4)
        let amount = max(1, Int(Double(available) * share))
        return (target.id, min(amount, available))
    }

    /// Whether to take the money and leave the round.
    ///
    /// A weak hand should be delighted; a strong one wants the showdown. The
    /// offer's size matters too — enough money outweighs a mediocre hand.
    public mutating func respondToSharah(
        _ offer: SharahOffer,
        hand: Hand,
        bet: Int,
        table: PublicTableView
    ) -> Bool {
        let strength = Self.handStrength(hand)
        let atRisk = max(bet, table.highestBet)
        let worth = atRisk > 0 ? min(1.5, Double(offer.amount) / Double(atRisk)) : 1
        let temptation = (1 - strength) + worth * personality.sharahAppetite + jitter()
        return temptation > 1
    }

    // MARK: - Dice

    private mutating func roll() -> Double {
        Double.random(in: 0..<1, using: &rng)
    }

    /// Noise, so two opponents holding the same cards need not do the same
    /// thing (SPEC.md §11).
    private mutating func jitter() -> Double {
        (roll() - 0.5) * personality.noise
    }

    private func pick(_ action: BetAction, from legal: [BetAction]) -> BetAction? {
        legal.contains(action) ? action : nil
    }
}
