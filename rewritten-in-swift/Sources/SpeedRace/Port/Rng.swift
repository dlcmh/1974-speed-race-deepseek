// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/rng.rs (canonical Rust game, repository root).
//
// A tiny deterministic xorshift generator.
//
// Keeping randomness local makes the traffic simulation reproducible in tests
// and avoids pulling in a dependency for a handful of calls per second.
//
// Port notes (docs/PORTING-JOURNEY.md):
//   * UInt64 wraps by definition in Swift, matching Rust's u64 arithmetic.
//   * `unit()` converts through `UInt32` so the types are exactly Rust's
//     (`u64 >> 40` to `u32`, divided by `1u32 << 24`). This is defensive: both
//     the explicit and the implicit spelling were measured to produce the same
//     bits on this toolchain, but the explicit form cannot depend on literal
//     inference (an earlier note in this file wrongly claimed the implicit form
//     produced a negative divisor — see the journey document's "false alarms").
//   * `fromTime()` uses the same nanosecond epoch and salt as Rust's
//     `Rng::from_time`.
import Foundation

public struct Rng: Sendable, Equatable {
    /// Current xorshift state.
    ///
    /// Deliberately visible: the parity harness and the `-Onone` investigation
    /// read it to locate exactly where a draw sequence diverges. Reading it is
    /// free, whereas any "peek by drawing" helper advances a *copy* and made
    /// earlier diagnostics ambiguous (docs/INVESTIGATION-parity.md).
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        // Rust: `seed.max(1)` — xorshift64 with a zero state never leaves zero.
        self.state = max(seed, 1)
    }

    /// Seed from wall-clock time, the way the app starts a fresh run.
    ///
    /// Rust uses `Duration::as_nanos()` since the UNIX epoch; using
    /// `timeIntervalSince1970 * 1e9` keeps the same magnitude so the first
    /// draw has the same distribution. Exact value parity with Rust is not
    /// meaningful here because it depends on when each app starts.
    public static func fromTime() -> Rng {
        let seconds = Date().timeIntervalSince1970
        let nanos = UInt64(bitPattern: Int64(seconds.rounded(.down) * 1_000_000_000))
        return Rng(seed: nanos ^ 0xA076_1D64_78BD_642F)
    }

    public mutating func nextU64() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }

    /// Uniform float in `[0, 1)` — Rust: `(self.next_u64() >> 40) as f32 / (1u32 << 24) as f32`.
    ///
    /// Every step is spelled out with explicit types: the shift yields a
    /// UInt32 (top 24 bits), which converts exactly to Float, and the divisor
    /// is the *unsigned* 2^24. Do not simplify this expression.
    public mutating func unit() -> Float {
        let high: UInt64 = nextU64() >> 40
        let bits = UInt32(truncatingIfNeeded: high)
        let numerator = Float(bits)
        let denominator: UInt32 = 1 << 24
        return numerator / Float(denominator)
    }

    /// Uniform float in `[min, max)`.
    public mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * unit()
    }

    /// Uniform integer in `[0, n)` — Rust: `(self.next_u64() % n as u64) as usize`.
    ///
    /// Both operands are converted to `UInt64` explicitly so the expression
    /// cannot depend on literal inference. (An earlier version of this comment
    /// blamed a debug-build miscompilation for a mismatch that later turned out
    /// to be three unrelated logic bugs in the simulation; see
    /// `docs/PORTING-JOURNEY.md` §6, false alarm FA-01.)
    public mutating func below(_ n: Int) -> Int {
        let bound = UInt64(n)
        if bound == 0 {
            return 0
        }
        return Int(nextU64() % bound)
    }
}
