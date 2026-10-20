# Investigation: renderer draws nothing through `MetalRenderer.render`

**Status: open.** The simulation and every non-window system are verified; the
off-window render path is not. This document records every experiment so the
next session does not repeat them.

## Symptom

`speed-race-render --render` writes a PNG whose entire canvas is the clear
colour. `metal_rect`-style draws reach the encoder but produce no pixels.

## What is verified working

Every one of these renders correct pixels on the same device (Apple M5):

| Experiment | Result |
| --- | --- |
| Hand-written shader, no vertex buffers | correct colour |
| `triangle_vertex`/`triangle_fragment` with `setVertexBytes` | correct |
| `primitive_vertex`/`primitive_fragment` with `setVertexBytes`, standalone pipeline | correct |
| Same, with `.shared` and `.managed` storage modes | correct |
| Two encoders in one command buffer, second draws | correct |
| `MetalRenderer.bisectStructure(0)` / `(1)` — inline texture, then guard-let helper | correct |
| `MetalRenderer.bisectInlineVsHelper` — all four combinations of helper × texture binding | correct |
| `MetalRenderer.bisectClearColor(true)` / `(false)` | **fails** |
| `MetalRenderer.bisectTwoEncoders(false)` / `(true)` | correct |
| `MetalRenderer.bisectEmptyCrt(true)` / `(false)` — the real `render` entry | **fails** |
| `MetalRenderer.bisectPassOrder` — CRT pass first or second | **fails** |
| `MetalRenderer.bisectFragmentTexture` | correct |
| `MetalRenderer.bisectWith(list:)` — a copy of `render`'s encode on a fresh command buffer | correct |
| `MetalRenderer.bisectRenderFlow` — `encodeOffscreenCabinet` + commit + read | **fails** |
| `MetalRenderer.bisectFirstPass(0/1/2)` — no first pass, CRT first pass, managed first pass | **fails** |
| `MetalRenderer.bisectStructure(0)`, and `bisectInlineVsHelper` | **correct** (contradicts the rows above) |

## The contradiction

Two groups of near-identical code disagree:

- `bisectStructure` / `bisectInlineVsHelper` / `bisectWith` create a texture,
  build a pass descriptor, call `encode`, end encoding, blit-synchronise,
  commit and read back — and get correct pixels.
- `encodeOffscreenCabinet` + `render`, and the `bisect*` variants that call
  those helpers, do the same statements and get clear-colour pixels.

The sets differ only in **which methods contain the statements**, not (after the
rewrites in this investigation) in what the statements are. This points at
incremental-compilation or code-generation behaviour in the `-Onone` debug
build rather than at a game-logic or Metal-usage error — the same class of
problem that made the earlier parity investigation so long (a stale build made
identical expressions return different values).

## Next steps, in order

1. **Clean build and retest.** `rm -rf .build && swift build && swift run
   speed-race-render --render all`. Every result above was obtained with
   incremental builds; the parity investigation shows this toolchain can carry
   stale objects across edits to a method body.
2. **If it persists:** move the offscreen encoding into a *top-level function*
   (not a method on `MetalRenderer`) that takes `device`, `queue`, `pipelines`
   and the lists, so the working and failing code share one implementation by
   construction rather than by copy.
3. **Then:** delete every `bisect*` helper from `MetalRenderer`; they are
   investigation scaffolding and must not ship (see DECISIONS P-0011).

## Ruled out (do not re-test)

- Pipeline state, blending configuration, missing `.shared`/`.managed` support.
- `setVertexBytes` payload size (chunks are now strictly under 4 KB; a
  4096-byte payload is rejected by this driver).
- Instance packing and alignment (verified as 16 correct floats per instance).
- Texture binding, texture storage mode, pass ordering, empty draw lists,
  clear-colour helpers, `try`/`guard` structure, number of instances.
- `MTLBuffer` uploads: they do not reach the GPU on this machine at all
  (DECISIONS P-0007); `setVertexBytes` is the supported path here.
