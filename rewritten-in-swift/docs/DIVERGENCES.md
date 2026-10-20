# Divergences from the canonical Rust game

Every place the Swift + Metal port intentionally differs from the canonical Rust
game (repository root, pinned at `d5f4420`), with the reason. Anything not
listed here is meant to be identical, and the parity suite proves it for logic.

## Gameplay and simulation

**None.** The ported simulation is bit-identical to Rust over roughly 18,000
replayed frames: countdown, 90-second clock, throttle/brake/steering physics,
edge clamping, traffic spawning and movement, collisions, track restarts,
overtaking and speed-based scoring, time extensions, best-score writes and
game-over. See `docs/PARITY.md`.

## Numeric implementation details (necessary, invisible)

### N-0001 — `TAU` is `6.2831855`, not `2.0 * Float.pi`

Rust's `std::f32::consts::TAU` has bit pattern `0x40C90FDB`; Swift's
`2.0 * Float.pi` produces `0x40C90FDC`. Exposed as `Float.rustTau`.

### N-0002 — `Rng.unit()` uses explicit `UInt32` conversions

`Float(bits) / Float(1 << 24)` binds the divisor to `Int64`, giving a negative
divisor. The port converts through `UInt32` so the divisor is `+16777216.0`, as
in Rust.

### N-0003 — Trigonometry goes through `rustSin`/`rustCos`

Swift's `Foundation.sin/cos(_: Float)` drift by one ULP from Rust at some
arguments. `Support/RustMath.swift` binds libm's `sin`/`cos` via
`@_silgen_name` and rounds once to `Float`.

**Known residual:** two attract-demo fields (`lean`, `lateral`) still differ by
at most 1 ULP on a small number of frames, because macOS's libm returns
different results for the same argument depending on the calling binary
(demonstrated with C, Rust and Swift probes). The parity suite compares those
two fields with a one-ULP tolerance and everything else exactly. The fields are
purely decorative wobble for the attract screen; they never feed the
simulation. See `docs/INVESTIGATION-parity.md`.

### N-0004 — Integer↔float casts are spelled out

Rust's `as` casts saturate; Swift's `UInt32(_:)` traps. `rustSaturating:` and
`Int32(rustSaturating:)` reproduce Rust's behaviour (NaN → 0, out-of-range →
clamped), with tests.

### N-0005 — `Rng` is a value type with readable state

Rust's `Rng` is `Clone`; Swift's is a `struct` with the same
`Sendable`/`Equatable` semantics. Its `state` is `public private(set)` so tests
can locate a divergence without consuming a draw.

## API and structure

### A-0001 — Test hooks are `public`

The Rust tests write `game.phase = Phase::Racing` and call private helpers
directly. Swift keeps `phase` read-only outside the type, so `Game` exposes
`forcePhase(_:)` and `updateExtensionsForTest()` explicitly. The app never
calls them.

### A-0002 — Points are a `NoticeText` enum, not a string

Rust stores `&'static str` in `Notice` and matches on its contents. The port
uses an enum (`go`, `crash`, `trackRestarted`, `timeExtended`) so the renderer's
switch is exhaustive and the parity trace can compare the raw value.

### A-0003 — Fixture format carries `game_seed` and `seed_mode`

Goldens record both the declared seed and the clamped value handed to the game,
plus whether the scenario is clock-seeded (`live`) or seeded, so the Swift
replay cannot guess wrong. The canonical Rust game needed three private items
widened to `pub(crate)` **in the generator's scratch copy only**; `src/` is
untouched.

## Deliberately not ported yet

These are gaps, not decisions; they are the remaining work:

- Metal rendering (draw list exists, no pipelines yet)
- Audio (`AVAudioSourceNode` DSP)
- Keyboard/gamepad input
- App shell, window, fullscreen, screenshot, high-score file
