import Foundation

/// The rules SPEC.md still leaves open.
///
/// Three rules used to live here — where a Sharah payment is funded from,
/// which zero balances eliminate, and who wins when two players cross the
/// target at once. All three are now **pinned** in SPEC.md §8, §12 and §13 and
/// implemented directly, so only the Sharah procedure remains configurable.
public struct GamePolicy: Hashable, Sendable {
    /// Who may offer Sharah to whom, and how often (SPEC.md §15.1). Still
    /// undecided, so still a knob rather than a rule in the engine.
    public var sharah: SharahPolicy

    public init(sharah: SharahPolicy = .standard) {
        self.sharah = sharah
    }

    public static let standard = GamePolicy()
}
