# Platform Portability

*Options for taking Speed Race beyond its current macOS build, and a
recommendation for choosing one without boiling the ocean.*

## TL;DR

1. **If the goal is “play it on my HarmonyOS laptop”, build a WASM/web version
   first.** It is the shortest path and does not require rewriting the game.
2. **If the goal is a native HarmonyOS app, or the core must serve several
   future platforms, use the hybrid architecture:** platform-neutral Rust core,
   a narrow C ABI, and a native ArkTS/C++ host.
3. **Do not rewrite the game in C++** just to reach HarmonyOS. The language is
   not the missing compatibility layer.
4. **Do not wrap it in Electron.** A 240 × 360 procedural game gains nothing
   from a browser runtime bundled as a desktop application.
5. **Decide the delivery surface before deciding the implementation.** Browser,
   native desktop app and HarmonyOS HAP are three different products, even with
   the same game inside.

This document separates the choices that are easy to confuse.

## The current situation

The game is a single Rust binary built on:

| Dependency | Role | HarmonyOS status |
| --- | --- | --- |
| `macroquad` | window, input, 2D rendering | no OHOS backend |
| `gilrs` | gamepads/racing wheels | no OHOS backend |
| `cpal` | real-time audio output | no OHOS backend |
| `std` | files, time, collections | Rust can target OHOS |

Rust itself supports `aarch64-unknown-linux-ohos`, so the code can compile for
HarmonyOS/OpenHarmony. The missing pieces are platform adapters: a native
window, a GLES context, input delivery, app lifecycle and audio output.

The simulation (`src/game.rs`, `src/road.rs`, `src/rng.rs`) is already
platform-neutral. The renderer (`src/gfx.rs`) is not; it is written in
macroquad draw calls. Audio is now a portable-ish synth wrapped in a cpal host
adapter.

## First, separate these questions

| Question | What it decides |
| --- | --- |
| Is a browser tab acceptable? | Whether WASM alone is enough |
| Must it be installed from AppGallery or run as a native HAP? | Whether a native host is required |
| Is HarmonyOS a one-off, or the first of several new hosts? | Whether a C ABI is worth it |
| Is a Mac `.app` the actual immediate need? | Whether this is really a packaging task, not a port |
| Is distribution legally cleared? | There is still no project license file; do not publish until decided |

A lot of portability anxiety disappears once these are answered.

## Options at a glance

| Option | Result on HarmonyOS | Relative effort | Reuse | Recommendation |
| --- | --- | --- | --- | --- |
| Keep macOS-only | none | zero | — | No |
| Native Windows/Linux builds | none | low–medium | high | Worth doing for desktop reach |
| Browser/WASM | playable in browser | low–medium | medium | **First spike** |
| Native HAP via Rust core + C ABI + ArkTS/C++ | native app | high | high | **Recommended if native is required** |
| C++ rewrite + OHOS host | native app | very high | low | Avoid |
| Electron wrapper | does not solve HarmonyOS | high | medium | Avoid for this game |
| Linux VM / Box64 on HarmonyOS | experimental | low | n/a | Try only as a demo |

## Option details

### A. Browser/WASM build

Compile the game to WebAssembly with WebGL rendering and run it in the
HarmonyOS browser. This is the shortest route to a playable experience.

Work required:

- add a wasm target/build pipeline;
- replace `gilrs` with the browser Gamepad API or keyboard-only input;
- replace the filesystem high score with `localStorage`;
- make F12 screenshots a browser download or remove the key;
- unlock WebAudio after a user gesture;
- adjust canvas sizing/fullscreen handling;
- host the build somewhere (GitHub Pages, a static host, or local files).

Acceptance criteria for a time-boxed spike:

- the cabinet and road render at a stable 60 fps;
- countdown, engine and effects are audible after the first user interaction;
- steering, gas, brake, pause and restart work;
- the high score survives a reload;
- no page scrolling or keyboard-focus traps.

The browser can be enough for casual play. It is not a native HAP, is not
distributed through AppGallery, and is not a solution for a signed desktop app.

### B. Native Windows/Linux desktop builds

The existing Rust code should build on both, though only macOS has been tested
interactively. This is normal desktop portability:

- Windows: MSVC toolchain + Build Tools; embed an icon and suppress the console
  window for release.
- Linux: build dependencies for cpal/ALSA and the windowing stack; package as
  AppImage or Flatpak for consistency.

This is useful for reaching desktop players, but does nothing for HarmonyOS.

### C. Native HarmonyOS HAP

A native HarmonyOS application needs:

```text
ArkTS/ArkUI shell
  ├── lifecycle, window, NAPI bridge
  └── XComponent
        │ native surface
C++ host
  ├── EGL/OpenGL ES rendering
  ├── input and lifecycle
  ├── OHAudio
  └── C ABI boundary
Rust core
  ├── simulation and scoring
  ├── audio synthesis
  └── frame generation (RGBA or render commands)
```

This is the hybrid architecture. It is a real project: DevEco Studio integration,
OHOS cross-compilation, native surface plumbing, audio backend, input events,
signing and device testing. It is not “compile the Rust binary and double-click.”

### D. C ABI hybrid

This is the same shape used by many mobile games:

```text
portable game core (C++, Rust, etc.)
        ↕ native interface
thin platform shell (Java/Kotlin, Objective-C, ArkTS/C++)
```

Historically, most of the game logic lived in C++; Android used JNI and iOS used
Objective-C++, while the platform layer owned lifecycle, input, store services
and sometimes the native surface. Rust changes the bridge language, not the
architecture.

For this game the boundary should be extremely narrow:

```c
typedef struct SRGame SRGame;

typedef struct {
    float steer;
    float throttle;
    float brake;
    uint32_t actions;
} SRInput;

uint32_t sr_abi_version(void);
SRGame  *sr_create(uint32_t seed, uint32_t best_score);
void     sr_destroy(SRGame *game);
void     sr_tick(SRGame *game, const SRInput *input, float dt);
void     sr_render_rgba(SRGame *game, uint8_t *rgba, uint32_t stride);
void     sr_fill_audio(SRGame *game, float *samples, uint32_t frames,
                       uint32_t channels, uint32_t sample_rate);
uint32_t sr_take_events(SRGame *game);
```

Principles:

- opaque handles, flat C structs, caller-owned buffers;
- no Rust types or references across the boundary;
- no panics across FFI; catch and return errors;
- version the ABI and generate the C header (`cbindgen` or similar);
- null-check pointers at the boundary;
- keep game state single-threaded; audio reads a small lock-free parameter
  snapshot or calls a dedicated render function.

**Rendering choice.** For this game, Rust can software-render the complete
240 × 360 RGBA frame. At 60 fps that is about 20 MB/s, trivial for a desktop or
laptop, and it makes every host a “upload one texture and draw a quad” problem.
The alternative is a display list or direct GLES calls; both reuse less code and
couple the core to graphics.

**Audio choice.** Extract the synthesizer so the host can ask for interleaved
f32 samples. cpal remains a desktop adapter; the HarmonyOS host uses OHAudio;
a future web host uses WebAudio. No locks or allocations in the audio callback.

**Policy change.** Today the crate forbids `unsafe`. A raw C ABI requires unsafe
at the boundary. If this path is taken, isolate it in an `ffi` module, update
AGENTS.md explicitly, and keep the safe core untouched.

### E. C++ rewrite

A C++ rewrite does not remove the ArkTS/XComponent/EGL/OHAudio work. It only
changes the language on the core side. You would still need a native host, and
you would lose the existing tested rules and audio design.

C++ has better HarmonyOS-adjacent tooling and examples. That is a real
advantage if starting from zero with an OHOS-capable engine. It is a poor reason
to rewrite a working 3,000-line Rust game.

### F. Electron

Electron solves desktop UI fragmentation by shipping Chromium. For this game it
means a large runtime around a tiny canvas, and it still does not run natively
on HarmonyOS. A browser/WASM build is the same web portability without the
desktop wrapper.

### G. Linux VM / Box64 on HarmonyOS

The HarmonyOS PC Linux environment and projects such as HarmonyBox can run Linux
binaries. A Linux build might work there, but GPU acceleration, audio, input and
performance are not guaranteed. Treat this as a demo path, not a product plan.

## Recommended sequence

### Phase 0 — decide the product

Write down one sentence:

- “I want to play it on my HarmonyOS laptop.”
- “I want a native HarmonyOS app for other people.”
- “I want a maintainable core for many platforms.”

The answer selects the path.

### Phase 1 — time-box a WASM spike

This is the cheapest experiment and produces a real, playable artifact. If the
browser meets the need, stop there.

Do not start a native port before this spike unless native HAP distribution is
already a firm requirement.

### Phase 2 — only if native is required: extract the core

- Create a platform-neutral `core` crate containing simulation and audio synth.
- Replace macroquad-dependent rendering with a software RGBA renderer, or
  explicitly choose a display-list/GLES boundary.
- Add the C ABI and generated header.
- Keep the current macroquad/macOS path alive as a reference host during the
  transition.

### Phase 3 — build the ArkTS/C++ host

- ArkTS shell with `XComponent`.
- C++ EGL/GLES host and OHAudio.
- NAPI bridge for lifecycle/input.
- CMake integration with the Rust `.so`/static library.
- Test on device and in the OHOS emulator.
- Package and sign the HAP.

### Phase 4 — packaging and CI

Only after something runs on the target:

- Mac `.app` bundle/notarization if needed.
- Windows MSVC build and installer/SmartScreen strategy.
- Linux AppImage/Flatpak.
- OHOS signed HAP.
- A CI matrix for format/tests/clippy, plus platform smoke tests where runners
  allow.

## What not to do

- Do not rewrite in C++ on the assumption that C++ “runs on HarmonyOS.” It
  doesn’t unless it targets OHOS and uses OHOS APIs.
- Do not port all four desktop platforms before validating the one that matters.
- Do not start with the C ABI before deciding what crosses it.
- Do not mix the simulation, renderer and host again after separating them.
- Do not publish a HAP or an app bundle until the licensing question is settled.

## Recommendation

**Build the WASM version first.** It is the one option that produces a playable
HarmonyOS result quickly, with a clear stop/go decision.

If the browser is not acceptable, use the **Rust core + C ABI + ArkTS/C++ host**
hybrid. It is the modern equivalent of the well-worn mobile C++ engine pattern:
portable rules, native surface, thin platform shell. That is the scalable
answer — but it is a project, not a packaging step.

## Open questions to resolve before Phase 2

- Is a native HAP mandatory, or is browser play enough?
- Which HarmonyOS version and device class is the baseline?
- Does ArkWeb provide the WebGL/WebAudio/input behavior required?
- Is a Huawei developer account and signing pipeline available?
- Is the game’s license settled for distribution?
- Will the core serve more than one future host, or is HarmonyOS a one-off?

## Related reading

- [ARCHITECTURE.md](ARCHITECTURE.md) — current system design and invariants
- [AUDIO_JOURNEY.md](AUDIO_JOURNEY.md) — how the audio backend reached cpal
- [DECISIONS.md](DECISIONS.md) — accepted design decisions
- [HARMONYOS_BACKEND.md](HARMONYOS_BACKEND.md) — deeper feasibility and milestone plan for a native OHOS backend
- [README.md](../README.md) — player-facing documentation
