import Foundation
import SpeedRace

// PORT OF: RngTests in src/rng.rs.
//
// Each test keeps the Rust test's name in snake_case → camelCase form so the
// two suites can be compared one-for-one.

let rngTests: [TestCase] = [
    TestCase("rng::values_stay_in_range") {
        var rng = Rng(seed: 1974)
        for _ in 0..<10_000 {
            let v = rng.unit()
            try expect(v >= 0.0 && v < 1.0, "unit() out of range: \(v)")
            let n = rng.range(-3.0, 7.0)
            try expect(n >= -3.0 && n < 7.0, "range() out of range: \(n)")
            try expect(rng.below(4) < 4, "below(4) out of range")
        }
    },
    TestCase("rng::same_seed_same_sequence") {
        var a = Rng(seed: 42)
        var b = Rng(seed: 42)
        for i in 0..<100 {
            try expectEqual(a.nextU64(), b.nextU64(), "draw \(i)")
        }
    },
    TestCase("rng::zero_seed_is_forced_to_one_like_rust") {
        // Rust: `Self(seed.max(1))`; without this, xorshift64 sticks at zero.
        var zero = Rng(seed: 0)
        var one = Rng(seed: 1)
        for _ in 0..<10 {
            try expectEqual(zero.nextU64(), one.nextU64(), "seeded sequence")
        }
    },
    TestCase("rng::unit_is_below_one_for_max_state") {
        // unit() divides by 2^24 *after* shifting, so the largest possible
        // draw is still < 1.0 — the property the Rust test relies on.
        var rng = Rng(seed: UInt64.max)
        for _ in 0..<10_000 {
            try expect(rng.unit() < 1.0, "unit() reached 1.0")
        }
    },
]
