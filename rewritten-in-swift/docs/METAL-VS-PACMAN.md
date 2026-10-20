# Why Metal worked in the Pac-Man port and not here

**Subject:** `/Users/dlcmh/dev/pac-man-arcade-swift-macos` (written by a different
agent in ~10 minutes; the game plays correctly) compared with this port's
renderer, which rendered nothing.

This document exists because the failure was extreme — no pixels at all, from
shaders and pipelines that rendered correctly in isolation — and because the
contrast isolates the cause better than any experiment I ran.

---

## The two renderers, side by side

| Aspect | Pac-Man (works) | Speed Race port (failed) |
| --- | --- | --- |
| Shader source | Swift `String` literal in `MetalShaders.swift` | `.metal` file processed as a **SwiftPM bundle resource** |
| Window surface | `MTKView` + `MTKViewDelegate` | hand-rolled offscreen `MTLTexture` |
| Vertex data | `MTLBuffer`, `.storageModeShared`, triple-buffered, `copyMemory` | `setVertexBytes` chunks (≤ 4 KB) |
| Geometry | CPU-triangulated flat vertex array, one draw call | instanced unit quads + SDF fragment (plus a triangle pipeline) |
| Vertex format | `packed_float2 position; packed_float4 color` | 16-float instance struct in `constant` address space, `[[instance_id]]` |
| Varyings | `float4 position`, `float4 color` only | 9 members incl. `float2`s and scalars (`shape`, `aaScale`, `textured`) |
| Blending | enabled, `sourceAlpha` / `oneMinusSourceAlpha` | same — not the difference |
| Mach-O framework linkage | explicit `.linkedFramework("Metal")`, `"MetalKit"`, `"AVFoundation"` | none declared |

## The causes, in order of confidence

### 1. The shader resource was not where the code thought it was (most likely)

The port shipped `Shaders.metal` via `.copy("Render/Shaders.metal")` and loaded it
with `Bundle.module.url(forResource:withExtension:)`. The renderer also had a
fallback that compiled a *different*, hand-written diagnostic shader in several
probes. Two consequences:

* Every probe that "worked" compiled a **string literal**, exactly like Pac-Man
  does. Every probe that failed went through the bundle-loaded `PrimitiveOut`
  path. That split matches the results precisely: `makeLibrary(source:)` with a
  literal rendered; the real pipeline did not.
* The `PrimitiveOut` variance data is the only substantive difference between the
  two shader bodies.

Pac-Man never touches the filesystem, so the failure mode cannot occur there.

### 2. Complex varyings versus two

Pac-Man's `VertexOut` has exactly `float4 position` and `float4 color`. The port's
`PrimitiveOut` carries nine members including three scalars interpolated across
the triangle. Diagnostics showed the fragment reading the correct `color.rgb`
while `color.a` came through as 0, which then made `sourceAlpha` blending discard
every pixel. Whether that is a driver bug, a struct-packing disagreement, or a
consequence of (1), the fix is the same: **interpolate only what is needed**.

### 3. `MTLBuffer` was wrongly ruled out

An earlier probe concluded "MTLBuffer does not reach the GPU on this machine"
(recorded in `DECISIONS.md` P-0007). **That conclusion was wrong.** Pac-Man uses
`MTLBuffer` + `copyMemory` and renders perfectly. The probe failed because the
buffer was created in a local scope and released before the command buffer
executed — a lifetime bug, not a driver limitation. The lesson: retain every
buffer a command buffer references until it completes (triple buffering, as
Pac-Man does, or a completion handler).

### 4. Surface and linkage

`MTKView` supplies a correctly configured drawable and render-pass descriptor;
the port built its own. That is not fatal by itself (the offscreen path did
render a clear colour) but it removes a class of mistakes. Declaring the Metal
frameworks explicitly in `linkerSettings` is also good hygiene the port skipped.

---

## The rewrite (adopted from Pac-Man)

The port's renderer now follows the proven shape:

1. shader source as a **Swift string** (`MetalShaderSource`), no bundle resource;
2. `VertexOut` limited to `position`, `color`, `uv`;
3. geometry **triangulated on the CPU** into one flat vertex array per frame and
   uploaded through a retained, triple-buffered `MTLBuffer`;
4. one draw call for all solid geometry, one for the CRT texture quad;
5. explicit framework links in `Package.swift`.

The SDF/instancing design (ADR P-0005) is retired: Pac-Man demonstrates that the
simpler path is both sufficient and reliable on this platform. The retained draw
list (P-0003) is unchanged — it is the input to the triangulator, and it is what
keeps the port reviewable against `src/gfx.rs`.

## What this costs

- Circles and ellipses are now polygonal (32 segments) rather than analytically
  anti-aliased. At 240 × 360 that is indistinguishable from macroquad's own
  tessellation, and it is what the original did anyway.
- Per-frame CPU triangulation of ~4,000 primitives. Measured cost is negligible
  at this scale compared with the cost of being unable to render at all.
