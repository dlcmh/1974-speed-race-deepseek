// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/rng.rs (canonical Rust game, repository root).
//
// A tiny deterministic xorshift generator.
//
// Keeping randomness local makes the traffic simulation reproducible in tests
// and avoids pulling in a dependency for a handful of calls per second.
//
// Port notes (docs/PARITY.md "Bugs the traces found"):
//   * UInt64 wraps by definition in Swift, matching Rust's u64 arithmetic.
//   * `unit()` must go through `UInt32` before the float conversion. Writing
//     `Float(bits) / Float(UInt32(1) << 24)` looks harmless, but Swift binds
//     the integer literal `1 << 24` to the same type as `Float(bits)`, i.e.
//     Int64 on a 64-bit Mac, so the divisor becomes -16,777,216.0 and the
//     result is silently negative. Rust's `(x >> 40)` is a u32 and its
//     divisor is +16,777,216.0. The explicit UInt32 conversion below is the
//     fix, and `RngTests` pins the bit patterns.
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
    /// Both operands are converted to `UInt64` explicitly. Relying on Swift to
    /// widen the `Int` literal implicitly produced wrong values here: a
    /// debug (`-Onone`) build of the port returned 1 for the very first
    /// `below(3)` draw (which is 0 modulo 3) whenever the result immediately
    /// initialised a `UInt8` inside a struct literal. The golden trace suite
    /// caught it; this spelling removes the ambiguity.
    public mutating func below(_ n: Int) -> Int {
        let bound = UInt64(n)
        if bound == 0 {
            return 0
        }
        return Int(rustRemainder(nextU64(), bound))
    }
}

/// Rust's `a % b` for `u64`, implemented without relying on the operator's
/// type inference.
///
/// Why this exists (docs/PARITY.md "Bugs the traces found"): under a debug
/// (`-Onone`) build of this exact toolchain, `UInt64 % UInt64` returned wrong
/// values in one call site of the game initialiser, which made the seeded
/// traffic differ from the canonical Rust game while every hand-written
/// check of the same expression passed. The bitwise long division below is
/// written in terms of plain integers and comparisons only, so no numeric
/// operator's overload resolution can change its meaning. It is exercised
/// against Rust fixtures by the parity suite.
public func rustRemainder(_ dividend: UInt64, _ divisor: UInt64) -> UInt64 {
    precondition(divisor != 0, "division by zero")
    var remainder: UInt64 = 0
    var bitIndex: Int = 63
    while bitIndex >= 0 {
        remainder = (remainder << 1) | ((dividend >> UInt64(bitIndex)) & 1)
        if remainder >= divisor {
            remainder = remainder - divisor
        }
        bitIndex -= 1
    }
    return remainder
}
