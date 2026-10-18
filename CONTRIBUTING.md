# Contributing

This is a small, finished game rather than a framework. Contributions should
keep it fast, legible and faithful to the cabinet-era feel.

Before opening a change, read [AGENTS.md](AGENTS.md) and skim
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). AGENTS.md is the operational
contract for both human contributors and AI agents.

## Setup

Requires a recent stable Rust toolchain with edition 2024 support (1.85+).

```sh
cargo run --release
```

The first build downloads macroquad and gilrs. On macOS no extra system
packages are needed. Linux builds may need the usual X11/ALSA development
packages required by macroquad audio.

## Definition of done

Every change should leave the repository in a releasable state:

```sh
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
```

Run the game for a short smoke test. For visual changes, verify the live window
is upright and the CRT/cabinet still compose correctly. A screenshot is useful
evidence, but it is not a substitute for checking the actual rendering path;
see the camera notes in AGENTS.md.

## What to change

- Game rules and tuning: `src/game.rs` and the matching tests.
- Road projection and curvature: `src/road.rs`.
- Cabinet, CRT, cars, typography: `src/gfx.rs`.
- Sound generation: `src/audio.rs`.
- Keyboard/gamepad mapping: `src/input.rs`.
- Window, frame loop, persistence: `src/main.rs`.

Keep rendering and simulation separated. If a rule is in `game.rs`, it should
be testable without opening a window.

## Art and audio policy

All visuals and audio are procedural. Do not add image, font or audio binaries
unless the project owner explicitly changes this policy. If you change the
camera or cabinet layout, update the two screenshots in `docs/` when the change
is intentional.

## Commits and push

The owner has authorized agents to commit and push as they see fit. Keep
commits focused, use imperative subject lines, and never force-push or rewrite
published history. The default branch is `main`; `origin` points at GitHub.

Do not commit:

- `target/` or other build output
- `speed-race-screenshot.png`
- `.speed_race_1974_highscore`
- `.DS_Store` or other macOS metadata
- credentials, tokens, `.env` files or generated logs

## Licensing

There is no license file yet. Do not add one or relicense the project without
the owner's explicit approval.
