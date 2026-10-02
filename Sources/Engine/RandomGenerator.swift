import Foundation

/// A `RandomNumberGenerator` that is either the system source or, given a
/// seed, a deterministic SplitMix64 stream. Tests seed it so a shuffle is
/// reproducible; the app leaves the seed off.
public struct RandomGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64?

    public init(seed: UInt64? = nil) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        guard var s = state else {
            var system = SystemRandomNumberGenerator()
            return system.next()
        }
        s = s &+ 0x9E3779B97F4A7C15
        state = s
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
