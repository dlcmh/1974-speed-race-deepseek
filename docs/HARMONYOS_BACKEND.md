# Growing a HarmonyOS Backend for miniquad and macroquad

*Feasibility, constraints and a milestone plan for reusing the existing
renderer on HarmonyOS NEXT.*

## Status

**Exploratory.** No HarmonyOS SDK, emulator or device is available in the
current development environment. This document is a plan for a hardware-driven
spike, not a claim that the backend already works.

If the only requirement is “play the game on a HarmonyOS laptop”, stop here and
read the browser/WASM path in [PORTABILITY.md](PORTABILITY.md). This document is
for the harder goal: a native HarmonyOS app that keeps macroquad as the
renderer.

## The fork point

Macroquad is the high-level 2D API. The platform work lives one layer down in
**miniquad**:

```text
game (this repository)
  └── macroquad
        └── miniquad
              ├── macOS
              ├── Windows
              ├── X11 / Wayland
              └── OHOS  ← missing
```

Forking macroquad alone will not help. The initial work belongs in miniquad: a
native window, an EGL/OpenGL ES context, input/event delivery, timing and
lifecycle. Macroquad can then sit on top with relatively few changes.

The HarmonyOS side of the bridge looks roughly like this:

```text
ArkTS / ArkUI
  XComponent  ── native surface handle
  key events, lifecycle, NAPI
        │
C++ NAPI shim  ── creates/destroys the native window
        │
miniquad OHOS backend (Rust)
  EGL + GLES, input queue, clock, surface events
        │
macroquad
        │
Speed Race
```

## What already exists

- Rust has an `aarch64-unknown-linux-ohos` target.
- HarmonyOS supplies a native NDK, NAPI, native-window APIs, EGL/GLES and
  OHAudio.
- The game's simulation is already platform-neutral.
- The audio synthesizer is close to platform-neutral; only the cpal host adapter
  is desktop-specific.
- macroquad/miniquad are permissively licensed and already have multiple
  backends, so there is a shape to follow.

## What is missing

- An OHOS miniquad backend.
- A HarmonyOS app host and build that can link the Rust library.
- A decision about who owns the frame loop.
- Backends for audio and gamepads.
- A device/emulator test loop.
- Packaging and signing.

The **frame-loop ownership** question is the biggest unknown. ArkUI owns the
application thread. Macroquad's main loop normally owns its process. A HarmonyOS
host will likely need to create the native surface on the UI side, then let a
dedicated render/game thread run miniquad/GL, with lifecycle and input events
forwarded across a queue. Surface loss, backgrounding and window resize have to
work in that model. This is more important than the GL clear colour.

## What an agent can and cannot do here

An AI coding agent can:

- fork and vendor miniquad;
- add a backend module and conditional compilation;
- write the NAPI/ArkTS host skeleton;
- add CMake and Rust cross-compilation configuration;
- build the game's core and run the existing macOS tests;
- write interfaces, tests, documentation and milestone logs;
- iterate on compiler and linker errors given the real SDK.

An AI agent cannot, in this environment:

- compile or link against the OHOS SDK without it being installed;
- prove that the surface, input, lifecycle or audio work on a device;
- sign and install a HAP without Huawei tooling and credentials;
- inspect the rendered result or listen to audio;
- guarantee correct FFI layouts and platform timing from documentation alone.

**Code volume is not the bottleneck. Hardware feedback is.** OHOS FFI is exactly
the kind of work where a plausible-looking implementation can fail on device.

## Required inputs

Before starting:

- [ ] A HarmonyOS SDK / DevEco Studio version matched to the target device.
- [ ] The OHOS NDK and sysroot available locally.
- [ ] A test device or emulator, with `hdc` log access.
- [ ] Permission to fork miniquad and pin it via Cargo.
- [ ] Approval for `unsafe` code in the platform boundary. The game crate
      currently forbids it; the fork/bridge is where it would live.
- [ ] A Huawei developer/signing setup if the result must be installable beyond
      developer mode.
- [ ] Confirmation that a native HAP is required rather than browser play.
- [ ] The licensing/distribution question settled before publishing a build.

## Milestone plan

Each milestone has a hard gate. Do not begin the next one until the previous one
is observed on the target.

### M0 — Toolchain proof

Build a trivial Rust `cdylib` for `aarch64-unknown-linux-ohos`, link it into a
minimal HAP, and call one Rust function from ArkTS/NAPI.

**Gate:** Rust code runs on device/emulator and logs a value.

### M1 — Hello triangle

ArkTS `XComponent` → NAPI → native window → EGL/GLES clear or triangle. This
does not involve miniquad or macroquad.

**Gate:** stable colour/triangle on the device, surviving resize and app
foreground.

This is the most important go/no-go point. If the native surface path does not
work, the rest of the plan is speculative.

### M2 — miniquad backend

Add the OHOS backend to a miniquad fork:

- native display/window wrapping the OHOS surface;
- EGL config/context creation and teardown;
- frame timing and swap buffers;
- input event queue;
- lifecycle pause/resume;
- window metrics and DPI handling.

**Gate:** a miniquad clear-colour example renders on device for a sustained
session.

### M3 — macroquad integration

Build macroquad against the fork and render simple shapes, text and a render
target. Verify orientation, high-DPI scaling, letterboxing and the existing
camera contracts.

**Gate:** macroquad's 2D test scene renders correctly; no upside-down or
stretched frames.

### M4 — Speed Race visual

Compile the game's renderer on OHOS. Temporarily replace device input and audio
with fixed input/silence.

**Gate:** the cabinet, CRT and road render on device; the game advances without
panics.

### M5 — Input and lifecycle

Forward keyboard events, pause/resume, fullscreen and app background events
across the bridge. Handle focus loss without losing the game thread.

**Gate:** a full race can be played with a keyboard; backgrounding does not
corrupt the surface or freeze the app.

### M6 — Audio

The current audio synth is portable; the output is not. Extract the mixer behind
a callback suitable for OHAudio, or add an OHAudio adapter.

**Gate:** engine audio, countdown, crash and extension sounds play on device
without periodic artifacts or underruns.

### M7 — Gamepad

`gilrs` has no OHOS backend. Options:

- implement OHOS input handling in the C++/ArkTS bridge;
- postpone gamepad support and ship keyboard-only;
- add a dedicated OHOS gamepad adapter.

**Gate:** whichever scope is chosen is documented and tested.

### M8 — Packaging

High-score path, screenshot location, app icon, HAP signing, install and launch
from the launcher.

**Gate:** a double-clickable, signed native app on a clean target device.

## Fork strategy

Use a separate miniquad fork or a `vendor/miniquad` checkout with a very small
patch surface. Do not copy the whole dependency tree into this repository.

Suggested:

```toml
[patch.crates-io]
miniquad = { git = "https://github.com/<owner>/miniquad", branch = "ohos-backend" }
```

Keep the OHOS code behind target-specific modules and feature flags so upstream
compatibility remains possible. If the backend stabilizes, upstreaming it is
better than maintaining a permanent fork.

Macroquad should remain pinned to its normal version where possible. If its
public API needs changes, those changes should be isolated and documented.

## Risks

- **Event-loop inversion.** ArkUI and macroquad both want to own the main
  thread. The host must define a render-thread model and event queue.
- **Surface lifecycle.** Backgrounding, resizing and losing the EGL surface are
  the likely sources of crashes and black frames.
- **FFI correctness.** NAPI signatures, native-window pointers, EGL configs and
  struct layouts must come from the actual SDK headers.
- **GLES differences.** Macroquad's shaders and render targets need verification
  on the target GPU/driver.
- **API drift.** HarmonyOS SDK versions may differ across laptop generations.
- **Audio thread constraints.** No locks or allocations in the audio callback.
- **Signing and install.** A build that runs in an emulator may not install on a
  sealed device without the right certificate.
- **Maintenance.** A private miniquad fork is a long-term cost; upstreaming is
  preferable.

## Go/no-go rules

- If M1 fails, pause the backend plan and use the WASM path or the C ABI hybrid
  instead.
- If M3 succeeds but M4 struggles only with game-specific dependencies, solve
  those behind host abstractions rather than widening the fork.
- If OHOS SDK requirements change or the device is unavailable, do not keep
  writing speculative FFI.
- If browser play is acceptable, do not start the fork at all.

## Definition of done

A native HarmonyOS port is done when, on a clean target device:

- the app launches from the launcher;
- the cabinet and game render at a stable frame rate;
- keyboard input and pause work;
- audio plays without artifacts;
- background/resume and fullscreen work;
- the high score persists;
- packaging and signing are reproducible;
- the source tree still passes its desktop tests and clippy gates.

## Recommended decision

This is a real engineering project, not a packaging step. It is most attractive
when all of these are true:

1. A native HAP is required.
2. The existing macroquad renderer is worth preserving.
3. A device and SDK are available for iteration.
4. There is an owner willing to accept a temporary fork and unsafe platform code.

If those are not true, prefer the browser/WASM spike described in
[PORTABILITY.md](PORTABILITY.md), or the narrower Rust-core + C ABI hybrid
approach.

## Related reading

- [PORTABILITY.md](PORTABILITY.md) — all platform options and recommendations
- [ARCHITECTURE.md](ARCHITECTURE.md) — current renderer and simulation design
- [AUDIO_JOURNEY.md](AUDIO_JOURNEY.md) — current audio architecture and history
- [DECISIONS.md](DECISIONS.md) — accepted technical decisions
