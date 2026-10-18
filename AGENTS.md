# AGENTS.md

Operational handoff for AI coding agents working in this repository.
Read this before changing code. If anything here conflicts with a direct
instruction from the repository owner, the direct instruction wins.

## TL;DR

This is a complete, playable Rust tribute to Taito's **Speed Race (1974)**.
It is a native desktop game built with macroquad, with no external art, font
or audio assets.

```sh
cargo run --release          # play
cargo fmt --check            # formatting gate
cargo test                   # 15 unit tests
cargo clippy --all-targets -- -D warnings
cargo build --release
```

The canonical remote is `origin`:
`https://github.com/dlcmh/1974-speed-race-deepseek.git`.
The default branch is `main`, and `origin/main` is its upstream.

## Current status

- Working title/attract screen, countdown, race, crash/restart and game-over loop.
- Procedurally drawn cabinet, CRT, cars, bitmap font and seven-segment LEDs.
- Procedural engine loops and arcade sound effects.
- Keyboard plus analog gamepad/racing-wheel input.
- Persistent high score.
- 15 unit tests; `cargo fmt`, `cargo clippy -D warnings` and release build pass.
- Tested interactively on macOS with Rust 1.97.1. The code targets edition 2024
  and declares `rust-version = "1.85"`.

## Non-negotiables

1. **Keep it shippable.** Every committed state must build and pass the gates
   below. Do not leave debug capture hooks, test toggles or dead experiments in
   `src/`.
2. **No asset pipeline.** The cabinet, fonts, sprites, road and audio are
   generated in code. Do not add images, TTF fonts or WAV files unless the
   owner explicitly changes that constraint.
3. **No unsafe code in this crate.** Keep it that way. `unsafe` in dependencies
   is outside our control.
4. **Preserve the feel.** The target is a fast, legible 1974 arcade game, not a
   simulation. Prefer small changes with a clear gameplay reason.
5. **Do not capture or hide the mouse.** The game has no mouse controls. Never
   call `show_mouse(false)` or otherwise grab the OS cursor: hiding it globally
   prevents the player from clicking other windows or the desktop until the
   game exits.
6. **No unreviewed licensing.** There is currently no project license file.
   Do not add, change or assume a license without the owner's approval.
7. **Never commit runtime output or secrets.** See `.gitignore`. Do not commit
   `.speed_race_1974_highscore`, `speed-race-screenshot.png`, credentials, tokens
   or `.env` files.

## Where things live

| Path | Responsibility |
| --- | --- |
| `src/main.rs` | window config, frame loop, cameras, screenshot, high-score file |
| `src/game.rs` | pure simulation: phases, traffic, scoring, crashes, extensions |
| `src/road.rs` | pseudo-3D projection and centre-line math |
| `src/gfx.rs` | all drawing: bitmap font, LEDs, road, cars, CRT, cabinet |
| `src/audio.rs` | in-memory WAV synthesis and playback |
| `src/input.rs` | keyboard and gamepad polling |
| `src/rng.rs` | deterministic xorshift RNG |
| `docs/ARCHITECTURE.md` | system design, constants, rendering contract |
| `docs/DECISIONS.md` | accepted design decisions and their trade-offs |
| `README.md` | player-facing documentation and controls |

## Gameplay model in one screen

- Start time: 90 seconds (`START_TIME` in `src/game.rs`).
- Max speed: 240 km/h. Traffic moves forward too; relative speed decides
  whether you approach or fall behind.
- Overtake score: `80 + speed * 0.42`, awarded once per car.
- First extension at 1,000 points, then every `1500 + count * 500` points.
  Each extension adds 20 seconds.
- Collision: spin-out, speed zeroed, track restarted, timer keeps running.
  A short invulnerability window follows the restart.
- Traffic is intentionally not allowed to form an unavoidable four-lane wall
  near the spawn point.
- The simulation advances only through `Game::update(Controls, dt)` and reports
  events through `take_events()`. Keep graphics and audio out of `game.rs`.

See `docs/ARCHITECTURE.md` for the exact phase graph and tuning constants.

## Rendering contract

The game intentionally renders at **240 × 360** into a render target, then
composes a **960 × 720** cabinet and scales the canvas to the window with
letterboxing.

There are two separate Y-axis quirks. Do not "clean them up" independently:

1. **Render-target texture:** draw it with `flip_y: true` in `src/gfx.rs`.
   Render-target textures are upside-down relative to screen textures.
2. **Canvas `Camera2D`:** `set_canvas_camera()` in `src/main.rs` negates
   `camera.zoom.y`. A screen camera with our custom viewport otherwise draws
   the cabinet vertically inverted.
3. **Screenshots:** `save_screenshot()` saves the raw framebuffer. It must not
   row-flip the image. Flipping here masks a broken display and produces an
   upright PNG while the live window is upside down.

A previous regression did exactly that: the live window was inverted, but the
screenshot path flipped the readback, hiding the bug. If you touch cameras,
viewport code, render-target drawing or screenshot handling, verify the
**live window**, not just the PNG.

### Retina / high-DPI

`screen_width()` and `screen_height()` are logical points. A manual
`Camera2D::viewport` is expressed in physical framebuffer pixels, so
`set_canvas_camera()` multiplies positions and sizes by `screen_dpi_scale()`.
Re-check letterboxing at a non-default window size and in fullscreen after
changing that code.

## Verification gates

Run these before every commit:

```sh
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
```

Also do a short launch smoke test:

```sh
./target/release/speed-race-1974
```

Kill it after a few seconds if you cannot interact with the window. At minimum,
confirm the process stays alive and the window content is upright.

### Visual verification without desktop screenshot permission

Normal macOS `screencapture` may be unavailable in agent sandboxes. When a
visual change needs evidence:

1. Temporarily add a local capture path that calls `save_screenshot` after a
   few frames.
2. Run it, inspect the PNG.
3. **Revert the temporary hook** before committing.
4. If the change is player-visible, update the checked-in screenshots in
   `docs/` only when the difference is intentional.

The shipped screenshots are:
`docs/title-screen.png` and `docs/gameplay.png`.

### Screenshot key

F12 writes `speed-race-screenshot.png` in the current working directory. On
macOS, F12 may require `Fn+F12` depending on the keyboard setting.

## Code style

- Rust 2024 edition; `cargo fmt` is authoritative.
- Clippy warnings are errors.
- Prefer small, named functions and module-level comments that explain *why*.
- Avoid `unwrap`/`expect` outside tests. Existing test-only unwraps are fine.
- No new dependency without a concrete need. Current direct dependencies are
  `macroquad 0.4.16` (audio feature) and `gilrs 0.11`.
- Keep the simulation deterministic when seeded. Randomness must go through
  `rng::Rng`.
- Tests should cover rules, projection math and generated audio headers, not
  pixel output. Add a regression test for every gameplay/logic bug that can be
  expressed without a window.
- Keep draw code tolerant of the low internal resolution. New HUD text should
  use `draw_pixel_text`, and new solid UI should use the existing palette.

## Git and publishing

The owner has granted agents authority to commit and push changes as they see
fit (recorded 2026-10-18). Use it conservatively:

- Work on `main` unless a branch is clearly warranted.
- Make a focused commit with a clear imperative subject, e.g.
  `Fix canvas camera orientation`.
- Push to `origin main` with upstream tracking. No force-push.
- Do not rewrite or amend already-pushed history unless the owner asks.
- Do not commit generated build output or runtime files.
- If a command needs interactive credentials and cannot authenticate, leave
  the work committed locally and report the condition; do not fabricate a push.

Suggested sequence after a completed change:

```sh
cargo fmt
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
git add -A
git commit -m "<imperative summary>"
git push origin main
```

## Known limitations / sensible next steps

These are optional, not commitments. If you pick one up, add tests and update
the docs in the same commit.

- The original cabinet offered difficulty modes; this tribute has a single
  time-ramped difficulty curve. A mode selector would be a natural addition.
- No two-player mode, force feedback, configurable controls or remappable
  keys.
- The game is a native desktop build; no WASM/web target is set up.
- Audio loops are deliberately synthetic. Engine buckets crossfade, and the
  one-second loop is generated with circularly filtered noise so it has no
  seam; timbre remains period-styled.
- There is no CI workflow yet. A macOS job running the four verification gates
  would be useful.
- High-score persistence is intentionally a tiny dotfile read/write with no
  file locking.

When in doubt, protect the arcade feel, keep the code testable, and document
the reason for the change.
