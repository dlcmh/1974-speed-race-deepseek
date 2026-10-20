# Decisions

Architecture decision records for the Swift + Metal port. Each entry states the
decision, the evidence, and the trade-off. Entries are numbered `P-nnnn`;
superseded entries stay in place with a pointer to their replacement.

The canonical Rust game is in the repository root (`src/`, pinned at `d5f4420`).
Where a decision exists because of a Rust property, the Rust behaviour is
quoted so the two can be checked against each other.

---

## P-0001 — Swift Package Manager, macOS 14, Swift 6

**Accepted.**

The port is a SwiftPM package with a library target (`SpeedRace`) and three
executable targets (`speed-race`, `parity-check`, `speed-race-render`).
macOS 14 gives Swift 6 language mode, `GameController`'s current controller API
and `AVAudioSourceNode` without availability workarounds.

**Why a library plus executables:** the app, the parity runner and the render
tool all link the same game code. Putting the game in an executable target
would force each tool to fork it.

**Trade-off:** a plain command-line executable has no app bundle, menu bar or
Dock presence. The windowed app will set an explicit activation policy and be
assembled by a small packaging script; no `.xcodeproj` is used because the
package builds and tests headlessly, which the agent harness needs.

---

## P-0002 — No third-party dependencies

**Accepted.**

The package depends only on Apple frameworks: Foundation, Metal, QuartzCore,
and (later) AVFoundation and GameController. The Rust original's rule is "no
asset pipeline"; the port extends it to "no dependency that could carry
assets". The PNG encoder, the parity harness and the RNG are all in-tree.

**Evidence that this is sufficient:** the whole test suite, the golden-trace
harness and headless rendering run with only Command Line Tools installed.

---

## P-0003 — Retained draw list instead of immediate-mode drawing

**Accepted.**

`src/gfx.rs` issues macroquad draw calls; the call order is the painter's
algorithm. The port records the same calls into `DrawList` — one Swift
statement per Rust call, same order — and Metal replays them.

**Why not draw directly to an encoder:** the same draw list is used for the
window, for headless screenshots and (later) for visual regression tests, and
it keeps the Rust-to-Swift correspondence reviewable as a diff.

---

## P-0004 — Shaders are compiled at launch, from a bundled `.metal` source

**Accepted.**

`Sources/SpeedRace/Render/Shaders.metal` is shipped as a resource and compiled
with `MTLDevice.makeLibrary(source:options:)` at startup.

**Why:** only Command Line Tools are installed on the development machine
(`xcrun metal` is absent), so there is no offline `.metallib` step. Metal
compiles the source at runtime in a few milliseconds at launch.

**Trade-off:** a shader syntax error is a runtime failure rather than a build
failure. Mitigated by `parity-check`'s `render::library` test, which compiles
the shaders and fails the gate.

**Revisit if:** a full Xcode installation is available in CI; switching to a
precompiled `default.metallib` is a `Package.swift` resource change.

---

## P-0005 — Two pipelines: one for primitives, one for triangles

**Superseded by P-0012.** Kept for the record: the instanced-quad + SDF design
rendered nothing on this platform. Diagnosis in
[METAL-VS-PACMAN.md](METAL-VS-PACMAN.md).

* **Primitive pipeline.** Every rectangle, rotated rectangle, circle, ellipse,
  line and textured quad is one instance of a six-vertex unit quad. Coverage is
  computed in the fragment shader from an analytic signed-distance function, so
  edges are anti-aliased at any scale and there is no CPU tessellation.
* **Triangle pipeline.** `fill_quad` in `gfx.rs` (road strips, shoulders, lane
  dashes, lamp posts, the glass reflection) becomes two exact triangles.

**Why not one pipeline:** triangles carry per-vertex positions and cannot use
the instanced-quad path without a bounding-box approximation that would change
road pixels. Keeping exact geometry for the road matters because the road is
most of the screen.

**Evidence:** the primitive pipeline renders correct shapes and colours in
isolation; the triangle pipeline likewise. See P-0007 for the upload mechanism.

---

## P-0006 — One y-down coordinate convention end to end

**Accepted.**

Draw-list coordinates are pixels with a top-left origin and y increasing
downwards, exactly as the Rust draw calls wrote them. The *vertex shaders* are
the only place that converts to clip space (`y_clip = 1 - 2*y/height`).

**Why this matters:** the Rust build carries two independent y flips —
`flip_y: true` when drawing the render-target texture and a negated
`Camera2D.zoom.y` for the cabinet camera — and `docs/DECISIONS.md` ADR-0007 in
the canonical repository records a real regression caused by them. The port has
no texture flip and no camera; the offscreen CRT texture is created and sampled
with the same y-down convention, so it arrives upright.

**Acceptance test:** the headless screenshot and the live window must show the
marquee at the top and the control deck at the bottom, with the readback
unflipped.

---

## P-0007 — Vertex data via `setVertexBytes`, chunked to 4 KB; no `MTLBuffer`

**Accepted, with a documented anomaly.**

All per-draw GPU data is passed with `setVertexBytes`, in chunks of at most
4096 bytes (Metal's limit for this path). Each chunk is packed into a `[UInt32]`
so the source storage is 4-byte aligned regardless of struct layout.

**Two findings drove this** (both verified with isolated tests):

1. `MTLBuffer` objects allocated in this process did **not** reach the GPU: an
   identical draw rendered correctly with `setVertexBytes` and rendered
   nothing with a buffer, on both `.shared` and `.managed` storage. The cause
   was not established; it is recorded here so the next person does not
   rediscover it. Revisit when a full Xcode toolchain is available.
2. `setVertexBytes` rejects lengths that exceed 4 KB with an assertion
   (`abort()` inside `AGXG17GFamilyRenderContext setVertexBytes:length:atIndex:`),
   and the cabinet issues thousands of primitives per frame, so chunking is
   mandatory rather than an optimisation.

**Trade-off:** repeated CPU copies per frame. The game draws a few thousand
primitives, which is trivial for modern hardware, and correctness comes first.

---

## P-0008 — Straight-alpha blending, matching macroquad's default

**Accepted.**

The colour attachment uses `src.a * src.rgb + (1 - src.a) * dst.rgb` with
`one`/`oneMinusSourceAlpha` for alpha. This is macroquad's default blend, which
`src/gfx.rs` relies on for every translucency effect (CRT halo, scanlines,
glass reflection, pause overlay).

---

## P-0009 — The CRT is an offscreen texture sampled with nearest filtering

**Accepted.**

The 240 x 360 scene renders into a `bgra8Unorm` texture; the cabinet pass
draws it as one textured quad at 1.5x with `constexpr sampler(filter::nearest)`,
matching `FilterMode::Nearest` on the macroquad render target. This is what keeps
the 1974 pixels chunky on a modern display.

---

## P-0010 — Headless rendering for verification

**Accepted.**

`MetalRenderer.render(drawable: nil)` renders the cabinet into an offscreen
texture and returns straight RGBA. `speed-race-render` writes PNGs with the
in-tree encoder.

**Why:** visual work must be verifiable without a window or screen-capture
permission, mirroring the canonical repo's "verify the live path, not just the
PNG" rule while making the PNG reproducible in CI.

**Trade-off:** the headless path is not the window path, so the live window
still needs a smoke test before any visual change is declared done.

---

## P-0011 — Investigation scaffolding never ships

**Accepted.**

Every `bisect*`, `renderDiagnostic*` and debug-print helper must be deleted
before a change is considered done, and probe code goes in a scratch executable
rather than the shared test runner. Two investigations in this port (parity,
then the renderer) were prolonged because probes accumulated in
`Tests/ParityCheck` and interfered with the gate's own results.

`INVESTIGATION-parity.md` records the same lesson from the other direction.

---

## P-0012 — CPU triangulation into one vertex buffer

**Accepted; supersedes P-0005.**

Every `DrawList` command is converted to triangles on the CPU
(`CanvasBuilder` → `VertexCanvas`) and submitted through a single
triple-buffered `MTLBuffer` per surface, with one draw call per contiguous run
of solid or textured geometry.

**Why:** this is the shape used by the Pac-Man port, which renders reliably on
the same machine where the instanced+SDF design produced no pixels at all
(docs/METAL-VS-PACMAN.md). It also removes the SDF fragment shader, the
16-float instance struct and the instancing path from the critical surface.

**Trade-off:** circles and ellipses are polygonal (32/40 segments) rather than
analytically anti-aliased. At 240 × 360 this is indistinguishable from
macroquad's own tessellation in `src/gfx.rs`.

---

## P-0013 — `MTKView` for the window, `AVAudioSourceNode` for sound

**Accepted.**

The playable app is AppKit (`NSApplication`, `.regular` activation policy) with
an `MTKView` subclass as content view and delegate. `MTKView` supplies the
drawable and render-pass descriptor, which is what the Pac-Man port uses.

Audio is `AVAudioEngine` + `AVAudioSourceNode` rendering the ported synth
(PORT OF `src/audio.rs`). Parameters are published through a small lock-free
struct of 32-bit words: single-copy atomic on arm64, worst case one frame of
staleness, no locking or allocation in the callback.

**Correction to P-0007:** `MTLBuffer` *does* work on this machine. The earlier
"buffers do not reach the GPU" finding was a lifetime bug — the buffer was
released before the command buffer executed. Buffers are now retained
(triple-buffered, as in the Pac-Man port).

---

## P-0014 — Painter order is preserved by segmenting the vertex buffer

**Accepted.**

`VertexCanvas` records ordered segments, each tagged solid or textured, and the
renderer switches pipeline per segment. Two ordering bugs were caught this way:
the road being flushed after the CRT overlay (drawing over the title text), and
the control deck — recorded *after* the CRT blit — being skipped entirely.

---

## P-0015 — Committing and pushing are delegated to the agent

**Accepted (owner instruction, 2026-10-20).**

The owner has granted standing authority for the agent to **commit and push
without asking**. This covers:

- staging changes, writing commit messages and pushing to `origin main` with
  upstream tracking;
- pushing follow-up fixes and documentation in the same working session;
- deciding when a change is complete enough to commit.

Standard git hygiene still applies and is not overridden:

- never force-push, never rewrite or amend pushed history;
- no build output, runtime files (`speed-race-swift-screenshot.png`,
  `.speed_race_1974_swift_highscore`), or secrets in a commit;
- keep commits focused and use imperative subject lines;
- if a push fails for credentials or network reasons, report the condition and
  leave the work committed locally — do not fabricate a successful push.

The canonical Rust game remains the reference implementation; this delegation
does not authorise changing it without a direct request.

**Recorded here rather than only in the conversation** so the working agreement
is visible to anyone reading the repository, and so future sessions do not
re-ask the question.
