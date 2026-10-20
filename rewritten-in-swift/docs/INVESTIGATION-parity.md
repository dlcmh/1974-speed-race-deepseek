# Investigation: golden-trace parity between the Rust game and the Swift port

**Status: resolved.** The parity suite (`swift run parity-check`) passes
21/21 checks in both debug and release builds, over ~18,000 replayed frames in
four scenarios, comparing f32 values as raw IEEE-754 bit patterns.

The investigation had a long false lead. This document records the real causes
first, then the false lead and why it wasted time, so nobody repeats it.

---

## What was actually broken

Three genuine port bugs were hidden behind a noisy, incorrect harness. Each was
found only after the harness itself was fixed.

### 1. The harness compared against a clock-seeded baseline

`Game::with_seed(best, seed)` in the canonical crate calls `Game::new(best)`
first — which seeds traffic from the **clock** RNG — and only then swaps in
`Rng::new(seed)`. So the traffic a seeded game starts with is not a function of
`seed`, and a "seeded" fixture was not reproducible at all.

Fix: the generator (`tools/parity-gen`) builds seeded scenarios explicitly —
`Game::new`, clear traffic, install `Rng::new(seed)`, `seed_traffic()` — with
the three private items widened to `pub(crate)` **in the scratch copy only**.
The canonical `src/` is never modified.

### 2. `moveTraffic` advanced every car on a crash frame

Rust iterates `for car in &mut self.traffic`, mutating in place. It breaks out
of the loop when a collision is detected, so cars visited *before* the crash
keep their new `z` and cars *after* it keep the old one.

The first Swift port copied each car into a local `var`, and the `break`
discarded the copy. Every car moved on the crash frame. Symptom: traffic `z`
diverged by ~8 units at frame 648 of a race.

Fix: mutate `traffic[index]` through the array, matching Rust exactly.

### 3. The `scored` flag was lost when a crash broke the loop

Related to the above: Rust sets `car.scored = true` and *then* may `break` for a
collision on the same car. Writing the flag back only at the end of the
iteration dropped it. Symptom: one traffic row differed only in `scored` at
frame 5969 of a race, with every position identical.

Fix: write `scored` through the array as soon as it is set.

### Also fixed (found by the suite, real but minor)

- **TAU constant.** Rust's `std::f32::consts::TAU` is `0x40C90FDB`; Swift's
  `2.0 * Float.pi` expression evaluates to `0x40C90FDC`. Every
  `rng.range(0.0, TAU)` was one ULP high. Fixed with `Float.rustTau`.
- **`Rng.unit()` divisor.** `Float(bits) / Float(1 << 24)` let Swift bind the
  divisor literal to `Int64`, producing `-16777216.0`. Rust divides by
  `+16777216.0`. Fixed with explicit `UInt32` conversions.
- **Trig implementation.** Swift's `Foundation.sin/cos(_: Float)` uses a
  single-precision path that disagrees with Rust's at some arguments. The port
  binds libm with `@_silgen_name` (see `Support/RustMath.swift`).
- **Fixture header.** Both the declared seed and the clamped `game_seed` are
  recorded, because `Rng::new` clamps zero to one.

---

## The false lead, and why it cost so much

For a long stretch the failing field was `lean` — a one-ULP difference in the
attract demo — and every isolated probe of `cos(x)` in the port *agreed* with
Rust. Hours went into libm, rounding modes, double rounding, FMA contraction and
`-Onone` versus `-O` behaviour.

**Why it happened:** `Tests/ParityCheck` had accumulated experimental cases
that constructed `Game` instances, and the runner executes every case. The
harness's own replay therefore ran after those cases, against a game whose
state had been disturbed by them. Isolated probes said one thing; the replay
did another; both were "correct" for what they measured.

**Lessons recorded for future work on this port:**

1. **Keep diagnostics out of the gate.** Investigation loops belong in a
   separate executable or behind a flag, never as cases in the suite. The
   `--only <name>` filter exists for exactly this and should be used from the
   first experiment.
2. **A one-ULP float difference is usually not a numerics problem.** Twice here
   it was a behavioural bug elsewhere (a discarded mutation) producing the same
   value through a different route.
3. **Fix the harness before trusting its verdicts.** A wrong baseline produces
   confident failures that point at innocent code.

---

## Current verification status

```
$ swift run parity-check
  ...
  21/21 checks passed
$ swift build -c release --product parity-check && .build/release/parity-check
  21/21 checks passed
```

Covered: RNG sequences, road projection and curvature, all game rules
(countdown, timer, overtaking, crashes, restarts, extensions, game over),
deterministic replays of full 90-second races seeded and unseeded, and the live
launch lifecycle. Comparison is exact except for the documented tolerance in
`docs/DIVERGENCES.md`.
