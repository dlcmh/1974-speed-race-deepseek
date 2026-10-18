# Architecture

`SPEED RACE (1974)` is a native macroquad game. It deliberately keeps the
simulation, presentation and platform plumbing in separate modules.

## Frame pipeline

```text
Input::poll
   │  Controls + hotkeys
   ▼
Game::update(controls, dt)
   │  Events: countdown, go, overtake, crash, extend, game over
   ├──────────────► ArcadeAudio (engine state + one-shots)
   │
   ▼
render 240 × 360 scene to RenderTarget
   │
   ▼
compose 960 × 720 cabinet on a letterboxed screen camera
   │
   ▼
next_frame()
```

The `Game` struct has no macroquad imports. It consumes a `Controls` value and
emits `Event` values. `main.rs` owns the window, audio, persistence and all
rendering.

## Modules

### `src/main.rs`

- Configures a 960 × 720 resizable window with `high_dpi: true`.
- Creates the 240 × 360 CRT render target with nearest-neighbour filtering.
- Runs the input → update → events/audio → render loop.
- Saves the high score to `~/.speed_race_1974_highscore`.
- Saves F12 screenshots to `speed-race-screenshot.png`.
- Composes the final canvas with a custom `Camera2D` viewport.

### `src/game.rs`

Owns all rules:

| Phase | Meaning |
| --- | --- |
| `Attract` | Animated title/demo road and traffic; no scoring or collisions |
| `Countdown` | Three-second start sequence; accepts throttle but does not move |
| `Racing` | Timer, physics, traffic, scoring, extensions |
| `Crashed` | Fixed spin/restart delay; timer continues |
| `GameOver` | Run finished; overlay and restart prompt |

Pause is a separate boolean on `Game`, valid during countdown/race/crash.
Rendering and audio freeze while paused, except that the frame still draws.

### `src/road.rs`

Defines the endless centre line as three sine waves and projects world distance
`z` to screen space:

```text
scale = 260 / (260 + z)
y     = 76 + (360 - 76) * scale
```

The camera is aligned with the road tangent, so the relative lateral offset is:

```text
C(distance + z) - C(distance) - tangent(distance) * z
```

Road strips are drawn back-to-front in 74 slices with quadratic z spacing.
Curvature also exerts a lateral pull on the player, making bends something to
drive against.

### `src/gfx.rs`

All drawing, including:

- Bitmap 5 × 7 font and its run-length rasteriser.
- Seven-segment LED panel and glow.
- Pseudo-3D road, lane dashes, roadside posts, cars, sparks.
- Title, countdown, pause, race notices and game-over overlays.
- The cabinet, marquee, side art, speedometer and control deck.
- CRT scanlines, vignette and a subtle reflection.

The cabinet canvas is 960 × 720. The CRT is drawn at
`CRT_X = 300`, `CRT_Y = 110`, scaled 1.5× from 240 × 360.

### `src/audio.rs`

Synthesizes mono 16-bit WAV data in memory at 22,050 Hz. There are six looping
engine buckets (fundamental frequency rises with speed), plus countdown, go,
crash, extension, game-over and overtake sounds. Audio failures are tolerated:
missing sounds simply do not play.

The engine bus uses equal-power crossfades between adjacent buckets when speed
crosses a threshold, so pitch changes do not restart the sound abruptly. Each
one-second loop also folds its extra tail into the head with a short crossfade:
filtered noise is not naturally periodic, and without this the loop would click
on every wrap. Both properties are covered by audio tests.

### `src/input.rs`

Combines keyboard state with the first connected gilrs gamepad. The mouse is
deliberately left alone: this game never hides or captures the OS cursor, so
the player can switch windows while it is running.

Input details:

- Left stick / wheel axis steers; d-pad adds digital steering.
- Right trigger or A/d-pad-up accelerates.
- Left trigger or B/d-pad-down brakes.
- Start pauses; A starts/restarts; Select quits.
- Button edges are tracked locally to avoid retriggering.

### `src/rng.rs`

A tiny xorshift generator. The constructor `Rng::from_time()` seeds normal
play; `Game::with_seed()` keeps tests reproducible.

## Gameplay tuning

| Constant | Value | Location |
| --- | --- | --- |
| Start time | 90 s | `START_TIME` |
| Max speed | 240 km/h | `MAX_SPEED` |
| Player collision z | 34 | `PLAYER_Z` |
| Collision window | ±38 z, ±0.20 lateral | `COLLISION_DZ/DX` |
| First extension | 1,000 pts | `start_race()` |
| Extension reward | +20 s | `update_extensions()` |
| Overtake points | `80 + speed * 0.42` | `move_traffic()` |
| Road view distance | 1,600 units | `road::VIEW_DISTANCE` |

The difficulty ramp is time-based: spawn interval falls from 1.02 s toward
0.58 s and the active-car cap rises from 13 toward 17. A spawn is skipped if
three cars already sit within 130 world units of the spawn band, preventing an
unavoidable wall.

## Screen-space orientation contract

This is the most likely source of future regressions.

- The CRT is a render target. When sampled with `draw_texture_ex`, it needs
  `flip_y: true` because render-target textures are vertically inverted.
- The cabinet camera created in `set_canvas_camera()` negates `zoom.y`.
  Without that, the whole live cabinet is upside down.
- `save_screenshot()` intentionally does **not** flip rows. The raw framebuffer
  is the truth. A row flip there hides screen-orientation bugs.

If changing any of these, the acceptance test is: the live window title bar is
normal, the marquee is at the top, the control deck is at the bottom, and F12
produces the same orientation.

## High-DPI and letterboxing

The virtual canvas is 4:3. Each frame the scale is:

```text
scale = min(screen_width / 960, screen_height / 720)
```

`Camera2D::viewport` uses physical framebuffer pixels, while screen dimensions
are logical points. The code therefore multiplies viewport dimensions and
offsets by `screen_dpi_scale()`. The background outside the viewport is black.
This has been verified on a Retina display; re-verify on other platforms after
touching those calculations.

## Test strategy

Unit tests live next to their modules:

- `game`: countdown, timer expiry, scoring, crash/restart, extensions, steering
  bounds.
- `road`: monotonic projection, smooth/bounded curves, zero relative offset at
  the camera.
- `audio`: WAV header and engine-loop duration.
- `rng`: range and determinism.

Rendering is not pixel-tested. Use the live game and screenshots for visual
changes, and keep the temporary capture workflow out of commits.

## Known technical limitations

- No CI; the verification gates are currently manual.
- No force feedback or configurable wheel mappings.
- High score path is `$HOME/.speed_race_1974_highscore` on all desktop
  platforms; it is not XDG/AppData-aware.
- Traffic is all same-direction four-wheel traffic; there are no oncoming
  vehicles, pedestrians or road hazards.
- The road is visual and planar; there are no hills or jumps.
