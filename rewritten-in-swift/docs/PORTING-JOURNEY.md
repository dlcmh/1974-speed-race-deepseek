# Porting Speed Race (1974) from Rust to Swift + Metal

### A complete account: what was built, every bug, every dead end, every alternative, and a playbook for the next port

This is the capstone document for the port in this directory. It assumes no
prior knowledge of the work and is written so that a future engineer — or a
future agent with no memory of these sessions — can repeat the process, avoid
the traps, and judge the result.

Where detail already exists elsewhere, this document summarises it and links
out. It deliberately **does not** omit failures: the failures are the most
transferable part.

Related documents:

| Document | Contents |
| --- | --- |
| [DECISIONS.md](DECISIONS.md) | 15 architecture decision records (P-0001…P-0015) |
| [DIVERGENCES.md](DIVERGENCES.md) | Every intentional difference from the Rust game |
| [INVESTIGATION-parity.md](INVESTIGATION-parity.md) | How bit-exact parity was reached, and what it cost |
| [INVESTIGATION-renderer.md](INVESTIGATION-renderer.md) | The renderer that rendered nothing |
| [METAL-VS-PACMAN.md](METAL-VS-PACMAN.md) | The comparison that solved it |
| [README.md](../README.md) | Running the game |

---

## 1. Summary card

| Fact | Value |
| --- | --- |
| Canonical source | `src/*.rs` in the repository root, pinned at `d5f4420` |
| Canonical size | 3,160 lines of Rust across 6 modules |
| Port size | ~4,900 lines of Swift across 24 files, plus fixtures and tooling |
| Wall-clock span | 2026-10-19 18:55 → 2026-10-20 10:40 (Asia/Kuala_Lumpur), across 15 agent turns and several long pauses |
| Third-party dependencies | none (Foundation, Metal, MetalKit, AppKit, QuartzCore, AVFoundation, GameController) |
| Assets | none — every pixel and sample generated in code, as in Rust |
| Parity gate | 22 checks; 4 golden fixtures; 18,000 replayed frames; f32 compared as raw bit patterns |
| Bugs found in the port | 12 real defects, 1 false alarm, 4 adaptations |
| Dead ends | 17 documented disproved hypotheses |
| Outcome | Feature-complete and playable; one documented 1-ULP cosmetic tolerance |

---

## 2. The two codebases, side by side

The Rust game is a complete, playable tribute to Taito's 1974 upright: a 240 ×
360 phosphor-green road scene inside a procedurally drawn cabinet, with
real-time synthesised engine audio. It is the *reference implementation* for
this port: where behaviour differs, Rust wins unless the difference is recorded
in `DIVERGENCES.md`.

| Concern | Rust | Swift port |
| --- | --- | --- |
| Window/input | `macroquad` | AppKit + `MTKView` |
| Rendering | `macroquad` immediate mode | retained draw list → CPU triangulation → Metal |
| Audio | `cpal` callback, custom synth | `AVAudioEngine` + `AVAudioSourceNode`, same synth |
| Gamepad | `gilrs` | GameController framework |
| Randomness | hand-rolled xorshift | hand-rolled xorshift (bit-identical) |
| Persistence | `~/.speed_race_1974_highscore` | `~/.speed_race_1974_swift_highscore` |
| Screenshot | `get_screen_data().export_png` | headless render + in-tree PNG encoder |
| Tests | 14 `#[test]` functions | 22-check custom runner (no XCTest available) |

### Module mapping

| Rust | Swift | Notes |
| --- | --- | --- |
| `src/rng.rs` | `Port/Rng.swift` | value type, same sequence |
| `src/road.rs` | `Port/Road.swift` | projection and sine centre line |
| `src/game.rs` | `Port/Game.swift` | all rules; no rendering or platform types |
| `src/gfx.rs` | `Render/Palette.swift`, `CrtScene.swift`, `CrtUI.swift`, `Cabinet.swift`, `SevenSegment.swift`, `DrawList.swift` | split by surface and by primitive recorder |
| `src/audio.rs` | `Support/AudioEngine.swift` | engine + six one-shots |
| `src/input.rs` | `Port/Input.swift`, `Port/GamepadInput.swift` | keyboard and controller |
| `src/main.rs` | `App/GameView.swift`, `AppDelegate.swift`, `Support/HighScore.swift`, `Support/Screenshot.swift` | frame loop and platform side effects |

---

## 3. Timeline

Times are local. The work spanned two calendar days with three long pauses;
"turn" numbers refer to agent turns in the original session.

| When | Phase | What happened |
| --- | --- | --- |
| 19 Oct 18:55 | Reconnaissance | Read all six Rust modules and five docs; probed the toolchain (Command Line Tools only, no `xcrun metal`; runtime `makeLibrary(source:)` works; M5 GPU). |
| 19 Oct 19:00 | Questions | Eight clarifying questions answered by the owner, fixing scope (full parity), packaging (SwiftPM), renderer style (1:1 draw list), audio (AVAudioSourceNode), identity (explicitly a port), parity method (golden traces), file separation, and git policy. |
| 19 Oct 19:02 | Scaffold | Package, directory tree, decision-log skeleton. |
| 19 Oct 19:03–19:07 | Simulation port | `Rng`, `Road`, `Game` transliterated; 19 checks passing; golden fixture generator built from verbatim copies of the Rust modules. |
| 19 Oct 19:07–20:09 | **Parity investigation** | The long one. Fixtures initially wrong; several false trails; session ended with a checkpoint moved out of the repository. |
| 19 Oct 21:00–21:20 | Resume and resolution | Clean rebuild, non-destructive RNG inspection, three real bugs found, gate green at 21/21, then 22/22. |
| 19 Oct 22:15–22:25 | Renderer attempt 1 | Instanced quads + SDF shader. Compiled, rendered nothing. |
| 20 Oct 08:26–08:54 | Renderer attempt 2 | Bisection across ~15 hypotheses; all disproved; release build also failed; stopped. |
| 20 Oct 10:31 | **Comparison** | Inspected `/Users/dlcmh/dev/pac-man-arcade-swift-macos`; identified three concrete differences; wrote `METAL-VS-PACMAN.md`. |
| 20 Oct 10:33–10:40 | Rewrite and publish | CPU triangulation renderer; app, input, audio; screenshots; commits `fa6bcfd`, `aff231f`, `2bfa719`, `f2745d1`. |
| 20 Oct 11:07 | Documentation | This document plus corrections to earlier false claims. |

### Human cost profile

The simulation port and the renderer rewrite were each roughly one working
hour. The two investigations consumed the rest: the parity harness (about three
hours, including one aborted session) and the first renderer design (about two
hours across two sessions). That ratio is the central lesson: **porting the
logic is cheap; proving equality and getting the platform layer right is the
work.**

---

## 4. Final architecture

### Data flow per frame

```text
Input.poll            keyboard + first gamepad/wheel → Controls, hotkeys
    │
    ▼
Game.update(controls, dt)       pure simulation; no Metal, no AppKit
    │  events: countdownBeep, go, overtake, crash, extend, gameOver
    ├──────────────► ArcadeAudio (engine parameters + one-shot voices)
    │
    ▼
CrtScene.draw(CrtDrawList)      240 × 360: sky, road, cars, sparks, UI
Cabinet.draw(CabinetDrawList)   960 × 720: chassis, marquee, LEDs, CRT blit, deck
    │
    ▼
CanvasBuilder.build → VertexCanvas    CPU triangulation, ordered segments
    │
    ▼
MetalRenderer.render
    ├── pass 1: CRT scene → 240×360 bgra8Unorm texture (nearest sampled)
    └── pass 2: cabinet → drawable or offscreen texture
                 letterboxed viewport, then present or read back
```

### Why this shape

The simulation is render-free because the Rust game's did the same and because
it makes the rules testable without a window. The draw list exists because the
Rust renderer's call order *is* its painter's algorithm, and recording it keeps
the port reviewable as a diff. CPU triangulation exists because the first,
cleverer renderer did not work (Section 7).

### Rendering contract

* Internal scene resolution is **240 × 360**; the cabinet canvas is
  **960 × 720**; the CRT is drawn at 1.5× with nearest sampling.
* One y-down, top-left-origin coordinate system end to end. The vertex shader
  performs the only clip-space conversion. There is no texture flip and no
  camera zoom flip, unlike the Rust build (which needs both; see the canonical
  ADR-0007).
* Letterboxing: `scale = min(drawableWidth/960, drawableHeight/720)`, viewport
  centred, background cleared to black.
* Straight-alpha blending throughout (`sourceAlpha` / `oneMinusSourceAlpha`),
  matching macroquad's default.

---

## 5. The parity harness

This is the most valuable artefact in the port, because it converts "looks
right" into a bit-level contract.

### Design

1. **The Rust side.** A generator copies `src/{game,rng,road}.rs` *verbatim*
   into a scratch crate (`tools/parity-gen/generate.sh`), adds a driver, and
   plays seeded input scripts through the **real** `Game`.
2. **The fixture.** JSON Lines, one line per frame, with every f32 stored as its
   raw IEEE-754 bit pattern (`"speed":1118845900`), plus a header and an RNG
   self-check block.
3. **The Swift side.** `Tests/ParityCheck` replays the same scripts through the
   ported `Game` and compares bit patterns.

### Fixture format (v2)

```json
{"header":true,"format":"speed-race-parity","version":2,"scenario":"seeded-race",
 "seed":1974,"game_seed":1974,"best":0,"rust_commit":"d5f4420","frames":6000,
 "dt":1015580809,"plays_race":true,"seed_mode":"seeded","start_restarts":1}
{"t":0,"in":[1065353216,...],"phase":"Countdown","paused":false,
 "speed":0,"lateral":0,...,"traffic":[[z,lateral,speed,kind,variant,scored,wobble],...],
 "spark_count":0,"events":["CountdownBeep"]}
{"rng_check":true,"seed":1974,"raw":[...],"unit":[...],"below":[...],"range":[...]}
```

Fields that matter for reproduction:

* `seed_mode: "seeded"` — the generator built the state explicitly (see below);
  every field is comparable.
* `seed_mode: "live"` — a clock-seeded launch; traffic and collision timing are
  not reproducible, so only lifecycle fields are compared.
* `game_seed` — the clamped seed actually given to `Rng::new`.
* `start_restarts` — how many `start_race()` calls happened before frame 0,
  because `start_race()` reseeds traffic from the *current* RNG stream (twelve
  draws later).

### The generator trick that made it possible

The canonical crate is a **binary**: `Game`, `Rng` and `Road` are not reachable
through a library interface. Three options were considered:

* **A (chosen).** Copy the three modules verbatim into a scratch crate,
  patching only `pub(crate)` visibility for `rng`, `traffic` and
  `seed_traffic()` — the visibility patch is applied by a Python heredoc inside
  `generate.sh` and **fails loudly if the canonical source stops matching**.
  Nothing in `src/` is touched.
* **B.** Add a `[[bin]]` to the canonical `Cargo.toml` pointing at a file
  outside the package. Works, but takes ownership of the canonical manifest.
* **C.** Split the canonical crate into library + binary. Cleanest long term,
  but it is a structural change to the game made on behalf of a port, so it
  needs the owner's decision.

### Why `with_seed` could not be used directly

`Game::with_seed(best, seed)` in the canonical crate calls `Game::new(best)`
first — which seeds traffic from the **clock** RNG — and only then swaps in
`Rng::new(seed)`. So the traffic a "seeded" game starts with is *not* a function
of `seed`. The generator therefore builds the state explicitly:

```rust
let mut game = Game::new(best);
game.traffic.clear();
game.rng = Rng::new(seed);
game.seed_traffic();
```

This is a faithful model of what the game does at `start_race()` time, with the
clock dependency removed. It was a genuine fixture bug before the change.

### What the harness proves — and what it does not

Proves: RNG sequences, road maths, every rule, every state transition, traffic
motion, collision timing, scoring, extensions, and the game-over path are
identical to Rust over 18,000 frames, down to the last bit — except the single
field listed in `DIVERGENCES` N-0003.

Does not prove: pixels, audio wave shapes, input timing, or the window. Those
have separate checks (a 20,000-pixel rectangle test, a shader-compiles test,
and a process-liveness smoke test) and still need human eyes for feel.

---

## 6. Bug catalogue

Every defect found during the port, with symptom, cause, fix and lesson.
"Real" means it changed behaviour; "hardening" means it made a fragile thing
explicit.

### B-01 — Fixtures depended on the clock (real, design)

* **Symptom:** A "seeded" fixture could not be reproduced by the Swift replay;
  traffic differed from frame 0.
* **Cause:** `Game::with_seed` seeds initial traffic from the clock RNG (above).
* **Fix:** generator constructs the start state explicitly.
* **Lesson:** a seed is not a promise of determinism if any constructor path
  touches the wall clock. Audit every RNG consumer at construction time.

### B-02 — Traffic moved differently on crash frames (real, behavioural)

* **Symptom:** traffic `z` diverged by ~8.8 units at frame 648 of a race; the
  crash happened on the same frame in both implementations.
* **Cause:** Rust iterates `for car in &mut self.traffic` and `break`s on
  collision, so cars visited before the crash keep their new `z` and cars after
  it keep the old. The first Swift version copied each car into a local and
  discarded the copy on `break`, so **every** car advanced.
* **Fix:** mutate `traffic[index]` through the array, exactly like Rust.
* **Lesson:** `&mut` + early `break` is an observable behaviour, not an
  implementation detail. Port the mutation granularity, not just the formula.

### B-03 — The `scored` flag was lost on a crash frame (real, behavioural)

* **Symptom:** one traffic row differed only in `scored` at frame 5969, with all
  positions identical.
* **Cause:** Rust sets `car.scored = true` and may then `break` for a collision
  on the same car; the port wrote the flag back only at the end of the
  iteration.
* **Fix:** write `scored` through the array as soon as it is set.
* **Lesson:** the same as B-02; they were one bug with two faces. Fix the data
  path, then re-run the whole trace.

### B-04 — Rust's `TAU` differs from Swift's `2.0 * Float.pi` (real, 1 ULP)

* **Symptom:** every `rng.range(0.0, TAU)` result was one ULP high, showing up
  as wobble-phase mismatches.
* **Cause:** `std::f32::consts::TAU` = `0x40C90FDB`;
  `2.0 * Float.pi` = `0x40C90FDC` (verified by printing bit patterns).
* **Fix:** `Float.rustTau = 6.2831855`.
* **Lesson:** mathematical constants are data. Copy the bit pattern, not the
  expression.

### B-05 — Trigonometry did not match Rust (real, 1 ULP on some inputs)

* **Symptom:** attract-mode `lean` differed by one ULP on a small number of
  frames even after everything else matched.
* **Cause:** Swift's `Foundation.sin/cos(_: Float)` uses a different
  implementation from Rust's, and macOS libm returns different results for the
  same argument depending on which binary calls it (demonstrated with C, Rust
  and Swift probes). Rust's optimised build matches the double-precision libm
  result rounded once to `f32` on the arguments the game actually uses.
* **Fix:** `rustSin`/`rustCos` bind libm with `@_silgen_name` and round once.
  `rustSinFloat`/`rustCosFloat` remain available for call sites that need the
  `sinf`/`cosf` result.
* **Residual:** two attract-demo fields (`lean`, `lateral`) still differ by at
  most 1 ULP on a few frames; the harness compares those two fields with a
  one-ULP tolerance and **everything else exactly**. Removing the tolerance was
  tested during the writing of this document and still fails at
  `seeded-attract` frame 38: `lean` `1056220228` vs `1056220229`.
* **Lesson:** for bit-exact ports, treat libm as platform data and pin it the
  same way as constants. Also: a 1-ULP difference is far more often a *logic*
  bug elsewhere than a numerics problem — both times it happened here, the
  first hypothesis was wrong.

### B-06 — The road was drawn over the title text (real, visual)

* **Symptom:** the attract screen's "SPEED RACE" title was partially covered by
  the road.
* **Cause:** `DrawList` only flushed its pending triangles at `finalize()`, so
  the road triangles (recorded early) were appended **after** the UI
  primitives (recorded later), reversing painter order.
* **Fix:** flush pending triangles whenever a primitive is appended.
* **Lesson:** a retained draw list must preserve *recording* order across
  primitive kinds, not just within a batch.

### B-07 — The control deck vanished (real, visual)

* **Symptom:** everything below the CRT was missing from the cabinet.
* **Cause:** the renderer drew "all solid geometry, then all textured
  geometry". The control deck is recorded **after** the CRT blit, so it fell
  into the skipped tail.
* **Fix:** `VertexCanvas` records ordered segments tagged solid or textured,
  and the renderer switches pipeline per segment.
* **Lesson:** "draw all X then all Y" is only valid if X and Y cannot
  interleave. In a painter's-algorithm renderer they always can.

### B-08 — Command buffer committed twice (real, crash)

* **Symptom:** `SIGABRT`: "commit an already committed command buffer".
* **Cause:** the offscreen path committed inside a helper and again in `render`.
* **Fix:** encoding and committing separated; one commit per buffer.
* **Lesson:** make ownership of "commit" explicit in the API shape.

### B-09 — `setVertexBytes` at exactly 4096 bytes (real, crash)

* **Symptom:** `SIGABRT` inside `AGXG17GFamilyRenderContext setVertexBytes:length:atIndex:`.
* **Cause:** Metal's per-call limit for this path; a 4096-byte payload is
  rejected.
* **Fix:** chunks sized strictly below the limit (63 instances of 64 bytes,
  or 127 triangle vertices of 32 bytes), documented in P-0012.
* **Lesson:** treat driver limits as inclusive-exclusive and encode that in the
  constant, not in a comment.

### B-10 — `MTLBuffer` released before the GPU used it (real, in a probe)

* **Symptom:** a draw rendered correctly with `setVertexBytes` and not at all
  with a buffer; this produced the false conclusion "buffers do not reach the
  GPU on this machine".
* **Cause:** the probe created the buffer in a local scope and dropped it
  before the command buffer executed.
* **Fix:** buffers are retained, triple-buffered, as in the Pac-Man port.
* **Lesson:** GPU resources must outlive the command buffer that references
  them. This single mistake cost hours and produced a wrong ADR (now corrected
  in P-0013).

### B-11 — Stale shader resource in the package (real, hygiene)

* **Symptom:** `Package.swift` still advertised `Render/Shaders.metal` after the
  shader moved to a Swift string; the file lingered in the tree.
* **Fix:** resource declaration and file removed.
* **Lesson:** after an architectural swap, grep for the old artefact's name.

### B-12 — Test hooks replaced direct field access (adaptation)

Rust tests write `game.phase = Phase::Racing` and call private helpers. The port
exposes `forcePhase(_:)` and `updateExtensionsForTest()` explicitly (P-0007 in
`DIVERGENCES`). This is an API difference, not a behaviour difference, and it is
documented so nobody mistakes it for one.

### False alarms (worth recording so they are not repeated)

* **FA-01 — "The RNG divisor is negative."** An early note claimed
  `Float(bits) / Float(1 << 24)` binds the literal to `Int64` and yields
  −16,777,216.0. Measured during this write-up: both spellings produce the
  identical result (`0.5960587`, bits `1058576206`). The explicit `UInt32` form
  is kept as hardening; the comment in `Rng.swift` has been corrected.
* **FA-02 — "`self.rng` was shadowed in the convenience initialiser."** A
  plausible reading of Swift's implicit-self rules, but never demonstrated to
  change behaviour. The explicit `self.` spelling is kept for clarity.
* **FA-03 — "`countdownNumber` clamps after casting."** Checked against
  `game.rs`; both implementations clamp in float then cast, and the saturating
  cast makes the orders equivalent. No change needed.

---

## 7. Dead ends and disproved hypotheses

The renderer investigation alone produced seventeen hypotheses. All are listed
because a future port will meet the same candidates.

### The renderer dead end in full

**Symptom.** Everything rendered as the clear colour. The same shader,
pipeline settings and instance data drew correctly in isolated probes but not
through `MetalRenderer.render`.

**What was tried, and what it showed:**

| # | Hypothesis | Result |
| --- | --- | --- |
| D-01 | Geometry wrong | Disproved: real vertex shader + constant-white fragment drew the exact rectangle. |
| D-02 | Instance data not reaching the GPU | Disproved: all 16 floats read back correctly through a probe fragment. |
| D-03 | SDF coverage maths wrong | Disproved: coverage computed correctly in isolation. |
| D-04 | Varying struct padding/order | Disproved: reordering `float4` before `float2`s changed nothing. |
| D-05 | Uninitialised struct members | Disproved: full aggregate initialisation changed nothing. |
| D-06 | Alpha channel missing from the target | Disproved: a no-`stage_in` fragment wrote alpha 0.5 correctly. |
| D-07 | Unbound fragment texture | Disproved: binding a dummy texture changed nothing. |
| D-08 | Texture aliasing between passes | Disproved: reordering and removing the CRT pass changed nothing. |
| D-09 | Two encoders in one command buffer | Disproved: a minimal two-pass experiment worked. |
| D-10 | Storage mode (.shared vs .managed) | Disproved: both behave identically. |
| D-11 | `setVertexBytes` chunk size | Partly real (B-09 aborts at 4096) but not the cause of "nothing draws". |
| D-12 | Optimisation level (`-Onone` vs `-O`) | Disproved: clean release build failed identically. |
| D-13 | Stale build artefacts | Symptom changed (black → garbage quads) but the bug survived. |
| D-14 | Blend factors | Disproved: they match the working Pac-Man port exactly. |
| D-15 | Bundle resource loading | **Contributing cause**: every working probe compiled a string literal; the failing path used the bundled `.metal`. |
| D-16 | Varying count/complexity | **Contributing cause**: the fragment saw correct `rgb` but zero alpha, which then made alpha blending discard everything. |
| D-17 | Something stateful across frames | Disproved: repeated identical renders were identically wrong. |

**The resolution** came from outside the loop: a *different* Swift/Metal
project (`pac-man-arcade-swift-macos`) that works on the same machine. Comparing
structures produced three concrete causes (shader delivery, varying complexity,
buffer lifetime) and a design to adopt (CPU triangulation, retained buffers).
That comparison is written up separately in [METAL-VS-PACMAN.md](METAL-VS-PACMAN.md).

**Why the loop was so long — process failures, honestly:**

1. **Probes polluted the gate.** Diagnostic cases were added to the shared test
   runner repeatedly; the runner executes every case, so later measurements were
   contaminated by earlier probes' side effects. Two rounds of this.
2. **Measurement helpers mutated state.** An early RNG "peek" advanced a copy
   through an accessor that itself drew values, making several traces
   self-contradictory. The fix was to expose `rng.state` for read-only
   inspection.
3. **Hypothesis-driven edits.** I twice edited the shader on a theory, then
   tested, then reverted. Each cycle cost several tool calls and produced no
   information when the theory was wrong.
4. **Late clean-rebuild discipline.** The first clean rebuild happened hours in.
5. **Not looking sideways sooner.** One inspection of a working sibling project
   ended the loop in minutes.

### Parity dead ends

| # | Hypothesis | Result |
| --- | --- | --- |
| P-D1 | `-Onone` miscompiles the RNG/constructor path | Disproved. Release and debug agreed; the real causes were B-01/02/03. |
| P-D2 | Double rounding on f64→f32 | Disproved for the arguments involved. |
| P-D3 | FMA contraction in `lean += (target - lean) * k` | Disproved; the difference was in the trig value, not the interpolation. |
| P-D4 | `Rng` should be a reference type | Tried and reverted; value semantics are correct and match Rust's `Clone`. |
| P-D5 | Fixture header seed vs `game_seed` | This one was **real** (B-01) but was initially mistaken for a build problem. |
| P-D6 | Build artefacts stale between runs | Real once (symptom changed after clean rebuild) but not the root cause. |

### The meta-lesson

Every long investigation here was long for the *same* reason: **the measurement
apparatus was broken or noisy, and I trusted it anyway.** The parity harness
produced confident, wrong failures because its fixtures were non-reproducible.
The renderer probes produced confident, wrong conclusions because their buffers
were freed and their shaders were different from the ones under test.

---

## 8. Alternative approaches considered

Each decision below was evaluated against at least one alternative. The chosen
option and the reason are recorded; the rejected options are recorded so a
future port can re-evaluate rather than rediscover.

### A-01 — Packaging: SwiftPM vs Xcode project vs bundle script

* **Chosen: SwiftPM**, macOS 14, Swift 6, library + executables.
* Rejected **`.xcodeproj`**: harder to build and diff headlessly, which this
  agent environment requires.
* Rejected **`.app` bundle script**: still worth adding for distribution, but it
  adds moving parts and does not change what the code does.
* Consequence: the app is launched from a terminal; `.regular` activation
  policy supplies a Dock icon and menu bar. A packaging step is listed as future
  work.

### A-02 — Test framework: XCTest vs Swift Testing vs custom runner

* **Chosen: custom runner** (`swift run parity-check`, exit code as the gate).
* Reason: the machine has **Command Line Tools only**; neither `XCTest` nor
  `Testing` is installed (`no such module 'Testing'`, `no such module 'XCTest'`).
* Consequence: 22 checks written as `TestCase` closures with a `--only` filter;
  no IDE integration. This also removed the temptation to hide a failing
  assertion behind a tolerance.

### A-03 — Shader delivery: bundle resource vs string literal vs offline metallib

* **Chosen: Swift string literal** (`MetalShaderSource.swift`).
* Rejected **offline `metallib`**: `xcrun metal` does not exist with Command
  Line Tools.
* Rejected **bundle resource**: the original choice, and a contributing cause of
  the renderer failure (every working probe used a literal).
* Trade-off: shader errors are runtime errors. Mitigated by a gate test that
  compiles the shaders and fails the run.

### A-04 — Renderer: instanced quads + SDF vs CPU triangulation

* **Chosen: CPU triangulation** into one vertex buffer per surface.
* Rejected **instanced quads with analytic SDF coverage**: elegant, fewer CPU
  cycles, and it *did not render at all* on this platform.
* Rejected **CoreGraphics/software rasteriser**: would have been playable
  sooner but abandons the Metal requirement.
* Trade-off: circles are 32-segment polygons; at 240 × 360 this matches
  macroquad's own tessellation.

### A-05 — Vertex upload: `setVertexBytes` vs `MTLBuffer`

* **Chosen: `MTLBuffer`** (`.storageModeShared`, triple-buffered, `copyMemory`).
* Reason: buffers can be large and reused; `setVertexBytes` has a 4 KB cap and
  aborted at that boundary. The earlier rejection of buffers was a lifetime bug
  (B-10).

### A-06 — Audio: `AVAudioSourceNode` vs AudioQueue vs pre-rendered buffers

* **Chosen: `AVAudioEngine` + `AVAudioSourceNode`**, the closest analogue of
  `cpal`'s callback.
* Rejected **`AudioQueue`**: more C-style plumbing, same capability.
* Rejected **pre-rendered PCM + `AVAudioPlayer`**: reintroduces exactly the
  looping-buffer design that the canonical game's ADR-0012 abandoned after
  fighting loop seams (`docs/AUDIO_JOURNEY.md` in the Rust repo).
* Consequence: the DSP is a direct port, so the port's engine has the same
  continuous-pitch behaviour and no seam.

### A-07 — Input: GameController vs IOKit HID vs SDL

* **Chosen: GameController framework**.
* Rejected **IOKit HID**: needs entitlements and per-device parsing.
* Rejected **SDL**: a third-party dependency for one feature.
* Consequence: first connected controller only; no force feedback (see
  `DIVERGENCES`).

### A-08 — Parity: bit-exact traces vs epsilon vs manual QA

* **Chosen: bit-exact golden traces**, with a documented one-ULP tolerance for
  two cosmetic fields.
* Rejected **epsilon comparison everywhere**: it hides real regressions —
  exactly the mistake the canonical repo warns about with its screenshot-flip
  regression.
* Rejected **manual QA only**: cannot prove state equivalence.

### A-09 — Generator: copy modules vs extra `[[bin]]` vs split crate

* **Chosen: verbatim copies** in a scratch crate, with a visibility patch
  applied by script and validated by assertion.
* Rejected **`[[bin]]` pointing outside the package**: works but takes ownership
  of the canonical manifest.
* Rejected **splitting the canonical crate**: best long-term shape, but a
  structural change to the game on behalf of a port; requires owner sign-off.

### A-10 — High score: shared file vs separate

* **Chosen: separate** (`~/.speed_race_1974_swift_highscore`), so the two
  implementations cannot clobber each other.
* Rejected **shared dotfile**: tempting for continuity, but the formats are
  independent and a future change in one would silently corrupt the other.

### A-11 — Text: port the bitmap font vs system font

* **Chosen: port the 5×7 font and its run-length rasteriser** verbatim.
* Rejected **system font**: would destroy the period look, and the port's whole
  point is visual fidelity.
* Consequence: `PixelFont.swift`-style tables in `Render/Palette.swift`, and a
  roster test asserting every string the game draws has glyphs.

### A-12 — Window: `MTKView` vs `CAMetalLayer` + `NSView`

* **Chosen: `MTKView`** (as in the working Pac-Man port).
* Rejected **manual `CAMetalLayer`**: more control, more ways to misconfigure
  the drawable and pass descriptor.

---

## 9. Compromises and accepted deviations

Each is a deliberate trade, with its risk and its revisit condition.

| # | Compromise | Why | Risk | Revisit when |
| --- | --- | --- | --- | --- |
| C-01 | Runtime shader compilation | No Metal toolchain in CLT | Shader error is a runtime failure | Full Xcode available → compile `metallib` at build time |
| C-02 | One-ULP tolerance on attract `lean`/`lateral` | macOS libm returns different values per calling binary | A future real drift of 1 ULP in those fields would pass | A toolchain/machine change, or if those fields ever affect gameplay |
| C-03 | Polygonal circles/ellipses (32/40 segments) | CPU triangulation | Slight faceting at large radii | If radii grow beyond the cabinet's fixed layout |
| C-04 | 15 MB of JSONL fixtures in the repo | Offline verification without Rust | Repo size; fixtures must be regenerated when Rust changes | If fixture size becomes a problem → compress or trim scenarios |
| C-05 | No force feedback | GameController haptics are optional | Less faithful wheel feel | If a wheel owner asks for it |
| C-06 | Separate high-score file and screenshot name | Prevent cross-implementation clobbering | Scores do not carry between games | If the owner prefers a shared profile |
| C-07 | Audio parameters are plain word/float fields, not `Atomic` | macOS 14 target; 32-bit accesses are single-copy atomic on arm64 | Theoretical torn or stale read | If targeting a non-arm64 platform or adding more parameters |
| C-08 | Screenshots come from a headless render | Deterministic and CI-friendly | Cannot prove the live window is upright | Already covered by a manual smoke test; revisit for CI screenshots |
| C-09 | No `.app` bundle | SwiftPM-only workflow | Launch from terminal; no Finder icon | When packaging for distribution |
| C-10 | No on-screen controller indicator | Not in the Rust game either | Player may not know a pad is connected | If asked |

### The one thing that is *not* a compromise

The simulation is bit-exact. Any future change to `Port/Game.swift`,
`Port/Road.swift` or `Port/Rng.swift` should be accompanied by a fixture
regeneration and a green gate, in the same commit.

---

## 10. Process retrospective

What went well:

* Reading the entire canonical source before writing code. Every constant and
  branch had a known home.
* Writing the parity harness *early*. It caught three real bugs that no amount of
  code reading would have found, and it is now a permanent asset.
* Recording decisions as they happened, including superseded ones. The decision
  log explains the current design without erasing the failed one.
* The sibling-project comparison. Looking at working code is a legitimate and
  underrated debugging technique.

What went badly:

* **Diagnostics in the gate.** Twice. The lesson is now an ADR (P-0011) and a
  test filter exists; future work must use it.
* **Trusting self-written measurement code.** A peek helper that consumed RNG
  draws invalidated several traces. Measurement code needs the same rigour as
  production code.
* **Hypothesis-first debugging.** Editing the shader on a theory and then
  testing is slower than bisecting with controls.
* **Late clean builds.** Always `rm -rf .build` before believing a cross-run
  difference.
* **Confidently documenting a wrong fact.** The `MTLBuffer` claim and the RNG
  divisor claim were both recorded as true and later disproved. The documents
  have been corrected, and this document records the corrections explicitly.
  For a project whose artefact is partly *documentation*, a wrong claim is a
  defect.

---

## 11. Baseline playbook for the next port

An ordered, gate-driven checklist distilled from this work. Each step has an
acceptance criterion; do not proceed past a red gate.

### Phase 0 — Decide and record (before code)

1. Write down what "done" means: feature list, platforms, packaging.
2. Record the decision policy: where commits go, what may be changed in the
   canonical project, and who owns licensing.
3. Identify the canonical commit you are porting. Pin it. Every fixture and
   comparison references it.
4. List every external dependency of the canonical project and find the platform
   analogue. Unknown analogues are the riskiest line items — schedule them
   early, not last.

**Gate:** a one-page scope note with the above.

### Phase 1 — Probe the toolchain before designing

5. Verify the build tool, test framework, shader compiler, audio API and input
   API actually exist and work on the target machine. Command Line Tools vs full
   Xcode is a material difference; so is a missing `metal` binary.

**Gate:** a hello-world that compiles a shader at runtime, opens an audio
stream, and reads a key.

### Phase 2 — Port the pure logic first

6. Port modules in dependency order (RNG → geometry → rules). Keep platform
   types out of the simulation.
7. Port the canonical tests one-for-one, keeping their names.
8. Add the same deterministic seam the original has (`with_seed`-style), even if
   it is test-only.

**Gate:** all ported unit tests pass.

### Phase 3 — Build the equivalence harness

9. Generate golden traces from the *real* canonical code, not from a
   reimplementation. Copying modules verbatim into a scratch crate is usually
   the least invasive option.
10. Encode floats as raw bit patterns. Store the seed, the clamp rule, the
    restart count and the mode in the header.
11. Compare exactly, then add tolerances deliberately, field by field, with a
    written reason.

**Gate:** traces replay bit-exactly, or a documented, minimal tolerance.

### Phase 4 — Port presentation

12. Record the original's draw calls into a retained list first; render them
    with the simplest working mechanism. Do not design a cleverer renderer until
    the simple one is on screen.
13. Preserve painter order across *all* primitive kinds, including any
    interleaved textured draws.
14. Verify with a known-shape pixel test (a rectangle of known size), then with
    the canonical screenshots.

**Gate:** a rendered frame that matches the reference image closely enough to
diff by eye, plus a numerical pixel test.

### Phase 5 — Platform layer

15. Window, input, audio, persistence, screenshots. Map hotkeys one-for-one and
    record any that cannot be mapped.
16. Smoke-test the actual window, not just a headless render. Orientation bugs
    are invisible to readback code that believes its own convention.

**Gate:** the process launches, stays alive, and responds to keys.

### Phase 6 — Publish

17. Update the decision log, the divergences list, the README and the
    investigation records.
18. Commit in focused steps with imperative subjects; push.
19. Correct any claim that later testing disproves. Treat documentation bugs as
    defects.

---

## 12. Verification recipes

```sh
cd rewritten-in-swift

# Everything the port claims to guarantee about behaviour.
swift run parity-check                     # 22/22

# The app builds and launches.
swift build
swift run speed-race-app                   # play; check window is upright

# Visual evidence without a window.
swift run speed-race-render --render all --out docs/

# Regenerate fixtures when the canonical Rust game changes.
tools/parity-gen/generate.sh               # requires cargo
swift run parity-check                     # must stay green
```

Useful one-off checks that live in the runner:

```sh
swift run parity-check --only rng::        # RNG sequence parity
swift run parity-check --only road::       # projection and curvature
swift run parity-check --only game::       # rules
swift run parity-check --only render::     # Metal rectangle test
swift run parity-check --only parity::     # golden traces
```

---

## 13. Appendix

### A. Metrics

| Metric | Value |
| --- | --- |
| Swift source lines | 4,882 (including tests and tools) |
| Largest files | `Port/Game.swift` 629, `Tests/ParityCheck/ParityTrace.swift` 437, `Render/CrtScene.swift` 400 |
| Fixtures | 4 files, 18,000 frames, 15 MB |
| Parity checks | 22 |
| Rust source lines | 3,160 |
| Commits | `fa6bcfd` (port), `aff231f` (git policy), `2bfa719` (gamepad), `f2745d1` (cleanup) |

### B. File map

```
rewritten-in-swift/
  Package.swift
  README.md
  Sources/SpeedRace/
    Port/        Rng, Road, Game, Input, GamepadInput
    Render/      Palette, CrtScene, CrtUI, Cabinet, SevenSegment,
                 DrawList, VertexCanvas, CanvasBuilder, MetalShaderSource,
                 MetalRenderer
    Support/     RustMath, PNGEncoder, AudioEngine, HighScore, Screenshot
  Sources/SpeedRaceApp/    main, AppDelegate, GameView
  Sources/SpeedRaceRender/ headless screenshot tool
  Sources/SpeedRaceCLI/    smoke runner
  Tests/ParityCheck/       main, RngTests, RoadTests, GameTests,
                            RosterTests, RenderTests, ParityTrace
  Fixtures/parity/         *.jsonl
  tools/parity-gen/        generate.sh, crate_root.rs, trace_fixtures.rs
  docs/                    DECISIONS, DIVERGENCES, INVESTIGATION-*,
                            METAL-VS-PACMAN, this file
```

### C. Glossary

| Term | Meaning |
| --- | --- |
| **canonical** | The Rust game in the repository root; the reference behaviour |
| **golden trace** | A recorded sequence of inputs and resulting state, replayed to prove equality |
| **fixture** | One JSONL file of golden frames plus header and RNG check |
| **draw list** | The retained record of Rust draw calls (rects, lines, quads, textured blit) |
| **segment** | A contiguous vertex range drawn with one pipeline |
| **ULP** | Unit in the last place — the smallest representable float difference |
| **`-Onone`** | Swift debug build setting (no optimisation) |

### D. Corrections log

Claims made during the work that later testing disproved, and where the
correction now lives:

| Claim | Status | Correction |
| --- | --- | --- |
| "`MTLBuffer` never reaches the GPU on this machine" | Wrong | Lifetime bug; see B-10 and P-0013 |
| "The RNG divisor is negative due to literal inference" | Wrong | Both spellings agree; see FA-01 and the corrected comment in `Rng.swift` |
| "`self.rng` shadowing was a real bug" | Unproven | Kept as clarity; see FA-02 |
| "The fixture seed is enough to reproduce a game" | Wrong | `with_seed` touches the clock; see B-01 |
| "The renderer failure is an `-Onone` miscompilation" | Wrong | Failed in release too; see the resolution in Section 7 |

---

*End of document. If you change the port, change this document: it is part of
the deliverable.*
