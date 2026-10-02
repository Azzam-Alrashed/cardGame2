import Foundation

public enum BettingDecision: Hashable, Sendable {
    case bet(Int)
    case withdraw
}

/// Decides for a non-human seat. Deterministic given its generator, so a whole
/// game can be replayed from a seed.
///
/// The original AI picked a random index into the legal bets and entered the
/// round when `index % random(2...4) == 0`, which made strong hands fold as
/// often as weak ones. This version reads the hand it was dealt and sizes its
/// bet against it, with a bluff and a flinch to keep it from being readable.
public struct AIStrategy: Sendable {
    /// Highest score any hand can reach (four aces), used to normalise.
    public static let maxHandScore = Hand(cards: Suit.allCases.map { Card(.ace, $0) }).score

    public struct Personality: Sendable {
        /// Below this confidence the AI folds rather than enter.
        public var foldBelow: Double
        /// Share of its stack it is willing to commit on a perfect hand.
        public var maxStackShare: Double
        /// Chance of entering on a hand it would otherwise fold.
        public var bluffChance: Double
        /// Chance of folding a hand it would otherwise play.
        public var flinchChance: Double
        /// Confidence under which it tries to buy its way out of the round.
        public var offerBelow: Double

        public init(
            foldBelow: Double = 0.45,
            maxStackShare: Double = 0.6,
            bluffChance: Double = 0.1,
            flinchChance: Double = 0.08,
            offerBelow: Double = 0.5
        ) {
            self.foldBelow = foldBelow
            self.maxStackShare = maxStackShare
            self.bluffChance = bluffChance
            self.flinchChance = flinchChance
            self.offerBelow = offerBelow
        }

        public static let cautious = Personality(foldBelow: 0.6, maxStackShare: 0.35, bluffChance: 0.03, flinchChance: 0.15)
        public static let balanced = Personality()
        public static let reckless = Personality(foldBelow: 0.3, maxStackShare: 0.85, bluffChance: 0.25, flinchChance: 0.02)
    }

    public var personality: Personality
    private var rng: RandomGenerator

    public init(personality: Personality = .balanced, seed: UInt64? = nil) {
        self.personality = personality
        self.rng = RandomGenerator(seed: seed)
    }

    /// How good this hand looks, from 0 to 1.
    public static func confidence(in hand: Hand) -> Double {
        Double(hand.score) / Double(maxHandScore)
    }

    public mutating func decideBet(hand: Hand, range: StakeRange) -> BettingDecision {
        guard !range.isEmpty else { return .withdraw }

        let confidence = Self.confidence(in: hand)
        var plays = confidence >= personality.foldBelow
        if plays, roll() < personality.flinchChance { plays = false }
        if !plays, roll() < personality.bluffChance { plays = true }
        guard plays else { return .withdraw }

        // Aim at a share of the stack scaled by confidence, then take the
        // highest legal bet that does not exceed it — falling back to the
        // cheapest legal bet when even that is too rich.
        let ceiling = Double(range.maximum) * personality.maxStackShare * confidence
        let target = ceiling >= Double(Int.max) ? range.maximum : Int(ceiling)
        return .bet(range.largestStake(upTo: target))
    }

    /// An amount to offer the top bettor to get out, or nil to stay in.
    public mutating func decideOffer(hand: Hand, range: StakeRange) -> Int? {
        guard !range.isEmpty else { return nil }
        let confidence = Self.confidence(in: hand)
        guard confidence < personality.offerBelow else { return nil }

        // The weaker the hand, the more it will pay to escape.
        let share = 1.0 - (confidence / personality.offerBelow)
        return range.stake(atFraction: share)
    }

    /// Whether the top bettor takes an offer. Worth taking when their own hand
    /// is shaky, since an accepted offer only pays if they win.
    public mutating func decideOfferResolution(hand: Hand, offer: Offer) -> Offer.Resolution {
        let confidence = Self.confidence(in: hand)
        return confidence >= personality.foldBelow ? .accepted : .rejected
    }

    private mutating func roll() -> Double {
        Double.random(in: 0..<1, using: &rng)
    }
}
