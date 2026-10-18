# Design decisions

Lightweight architecture decision records. Update this file when a decision is
reversed or materially changed. Keep entries short and concrete.

## ADR-0001 — Macroquad as the rendering/window layer

**Accepted.**

Use `macroquad 0.4.16` instead of a hand-rolled platform layer. It provides a
cross-platform native window, 2D primitives, render targets and audio with a
small API. Game rules stay independent of it so the dependency can be replaced
if necessary.

## ADR-0002 — Procedural presentation, no external assets

**Accepted.**

The cabinet, pixel font, cars, road, LEDs and sounds are generated in code.
This keeps the repository self-contained and makes visual changes inspectable
in diffs. A custom 5 × 7 bitmap font is used instead of a TTF because it gives
precise control at the low internal resolution.

## ADR-0003 — 240 × 360 scene inside a 960 × 720 cabinet

**Accepted.**

The gameplay is rendered at 240 × 360 to preserve chunky 1974 pixels, then
scaled 1.5× into a portrait CRT and composed on a 960 × 720 cabinet canvas.
The final canvas is letterboxed to the window. This gives a readable arcade
cabinet on desktop displays without making the gameplay playfield large enough
to lose its period character.

## ADR-0004 — Pseudo-3D road with sine-wave curvature

**Accepted.**

The road uses a projection (`scale = 260 / (260 + z)`) and a continuous
three-sine centre line rather than a tile map or full 3D renderer. It produces
smooth sweepers with very little code, allows exact collision math, and keeps
the entire scene deterministic. The tangent is subtracted so that a steady
curve does not permanently drag the horizon off-screen.

## ADR-0005 — Cabinet HUD plus a minimal in-screen strip

**Accepted.**

The original upright displayed score and time on an auxiliary LED panel. We
reproduce that as the right-hand scoreboard, including next-extend and best
score. A tiny speed/time strip remains at the top of the CRT so players do not
have to look far from the road. Duplication is intentional for playability.

## ADR-0006 — Simulation owns rules; app owns side effects

**Accepted.**

`Game::update` is render-free and side-effect-free apart from its own state and
event queue. Audio and the high-score file are handled by `main.rs`. This makes
the rules deterministic and directly testable without a window or audio device.

## ADR-0007 — Screen camera Y flip and raw screenshots

**Accepted; regression history.**

The whole canvas previously rendered upside down. The initial fix flipped the
rows in `save_screenshot`, which made saved PNGs look correct while the live
window stayed inverted. That was a false fix: the screenshot was accurately
reporting the display. The actual correction is the Y zoom flip on the
screen-space `Camera2D` in `set_canvas_camera()`.

The render-target draw still uses `flip_y: true`; that is a separate, valid
texture-orientation need. Screenshot readback is now saved raw. Changes to this
area require verifying the live window, not just the PNG.

## ADR-0008 — Fixed 90-second run with score extensions

**Accepted.**

Keep the original's 90-second starting clock and score-triggered time
extensions rather than a fixed lap count. This creates the short, tense arcade
loop. The first extension is at 1,000 points; subsequent thresholds increase
faster (1,500 then 2,000 then 2,500 points beyond the previous target).

## ADR-0009 — Crash resets the track but not the clock

**Accepted.**

A collision zeroes speed, spins the car, clears and reseeds traffic, and resumes
at the start. The timer keeps running during the crash and restart. This
preserves the original's punishment while keeping a run to a bounded length.

## ADR-0010 — Gamepad/wheel support through gilrs

**Accepted.**

Use `gilrs` to expose analog steering and trigger pedals, with keyboard
fallbacks. Only the first connected pad is used. This honours the cabinet's
wheel-and-pedal origin without requiring bespoke hardware drivers or force
feedback.

## ADR-0011 — High score in a dotfile

**Accepted, low stakes.**

Persist only the best score to `~/.speed_race_1974_highscore` with a tiny
read/write. It is not a general settings system and has no file locking. If
settings/rebindable keys are added, revisit and likely move to a platform
configuration directory.
