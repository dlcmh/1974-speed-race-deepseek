#include <metal_stdlib>
using namespace metal;

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the 2D drawing primitives that macroquad gave src/gfx.rs. Metal
// has no `draw_rectangle`/`draw_circle`/`draw_line`, so the port keeps the
// *draw list* identical — same shapes, same order, same colours — and
// rasterises each shape with an analytic signed-distance function inside one
// instanced pipeline. Rectangles, rotated rectangles, lines, circles and
// ellipses all become instances of the same six-vertex unit quad whose
// fragment coverage is computed from the distance to the ideal outline.
//
// Coordinates: vertices arrive in destination pixels with a top-left origin
// and y increasing downwards, the convention every Rust draw call used. The
// vertex shader converts to clip space (y up) exactly once. The Rust
// macroquad build needed two independent y flips (render-target `flip_y` and
// a negated `Camera2D.zoom.y`); the port has this single, documented
// conversion instead (docs/DECISIONS.md P-0006).

struct Viewport {
    float2 size;
};

// Matches PrimitiveInstance in DrawList.swift. 16 floats = 64 bytes.
struct PrimitiveInstance {
    float2 center;        // 0
    float2 halfSize;      // 8   (rect/ellipse) or (halfLength, halfThickness) for lines
    float2 axis;          // 16  (line only) unit direction
    float4 color;         // 24
    float2 uvOrigin;      // 40
    float2 uvSize;        // 48  (0, 0) disables texturing
    float shape;          // 56  0 = rect, 1 = ellipse, 2 = line
    float aaScale;        // 60  destination pixels per draw-list pixel
};

struct PrimitiveOut {
    float4 position [[position]];
    float4 color;
    float2 local;       // position in the primitive's local box, -1...1
    float2 halfSize;
    float2 axis;
    float2 uv;
    float shape;
    float aaScale;
    float textured;
};

vertex PrimitiveOut primitive_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant PrimitiveInstance *instances [[buffer(0)]],
    constant Viewport &viewport [[buffer(1)]])
{
    constant PrimitiveInstance &inst = instances[iid];

    float2 local;
    switch (vid) {
        case 0: local = float2(-1.0, -1.0); break;
        case 1: local = float2( 1.0, -1.0); break;
        case 2: local = float2(-1.0,  1.0); break;
        case 3: local = float2(-1.0,  1.0); break;
        case 4: local = float2( 1.0, -1.0); break;
        default: local = float2( 1.0,  1.0); break;
    }

    // Local box (x along the shape axis, y across it) -> pixel space.
    float2 along = float2(inst.axis.y, -inst.axis.x);
    float2 offset = float2(local.x * inst.halfSize.x, local.y * inst.halfSize.y);
    float2 pixel = inst.center + inst.axis * offset.x + along * offset.y;

    // Every member is initialised in one aggregate expression. Leaving any
    // field unset left the rasteriser with undefined varying inputs on this
    // driver: the fragment saw the correct `color.rgb` but always an alpha of
    // 0, which made straight-alpha blending discard every primitive
    // (docs/INVESTIGATION-renderer.md).
    PrimitiveOut out = {
        float4(0.0),
        inst.color,
        local,
        inst.halfSize,
        inst.axis,
        inst.uvOrigin + (local * 0.5 + 0.5) * inst.uvSize,
        inst.shape,
        inst.aaScale,
        (inst.uvSize.x != 0.0 || inst.uvSize.y != 0.0) ? 1.0 : 0.0,
    };
    out.position = float4(
        pixel.x / viewport.size.x * 2.0 - 1.0,
        1.0 - pixel.y / viewport.size.y * 2.0,
        0.0,
        1.0);
    return out;
}

// Signed distance, in *local box units* (local space is a unit box, so the
// distance is anisotropic for non-square shapes).
float shape_distance(float2 p, float2 halfSize, float shape) {
    if (shape < 0.5) {
        // Axis-aligned box in local space whose edge is at |p| = 1.
        float2 d = abs(p) - float2(1.0);
        return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
    }
    if (shape < 1.5) {
        // Ellipse: map to a unit circle. The local box is (-1..1), so the
        // exact distance stays negative inside the ellipse.
        return length(p) - 1.0;
    }
    // Line: a capsule along x with half-extent 1 and half-thickness t,
    // where t = halfSize.y / max(halfSize.x, eps) so the cap-end distance is
    // preserved. (x is clamped to [-1, 1] by the unit box.)
    float t = halfSize.y / max(halfSize.x, 0.0001);
    float2 q = float2(abs(p.x) - 1.0, abs(p.y) - t);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0);
}

fragment float4 primitive_fragment(
    PrimitiveOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]])
{
    float4 color = in.color;

    if (in.textured > 0.5) {
        // Nearest sampling keeps the 240 x 360 CRT crisp at 1.5x, matching
        // macroquad's FilterMode::Nearest on the render target.
        constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
        float4 texel = texture.sample(nearest, in.uv);
        return texel * color;
    }

    // `shape_distance` returns the signed distance in *local* units, where the
    // shape's edge sits at |p| = 1 (and the box spans -1...1). One local unit
    // is therefore the shape's half extent, so multiplying by the smaller half
    // extent converts to destination pixels. Edges are anti-aliased over one
    // pixel centred on the boundary.
    float2 scale = max(in.halfSize, float2(0.0001));
    float d = shape_distance(in.local, in.halfSize, in.shape);
    float px = d * min(scale.x, scale.y) * in.aaScale;
    float coverage = saturate(0.5 - px);
    color.a *= coverage;
    return color;
}

// ---------------------------------------------------------------------------
// Triangle pipeline: used only by `fill_quad` in gfx.rs (the road, shoulders,
// lane dividers, lamp posts and the glass reflection). Unlike the primitive
// shader this one consumes the exact triangle vertices, so there is no
// distance approximation at all.
// ---------------------------------------------------------------------------

struct TriangleVertex {
    float2 position;  // destination pixels, y down
    float4 color;
    float _pad0;  // matches TriangleVertex in DrawList.swift (32-byte stride)
    float _pad1;
};;

struct TriangleOut {
    float4 position [[position]];
    float4 color;
};

vertex TriangleOut triangle_vertex(
    uint vid [[vertex_id]],
    constant TriangleVertex *vertices [[buffer(0)]],
    constant Viewport &viewport [[buffer(1)]])
{
    TriangleVertex v = vertices[vid];
    TriangleOut out;
    out.position = float4(
        v.position.x / viewport.size.x * 2.0 - 1.0,
        1.0 - v.position.y / viewport.size.y * 2.0,
        0.0,
        1.0);
    out.color = v.color;
    return out;
}

fragment float4 triangle_fragment(TriangleOut in [[stage_in]]) {
    return in.color;
}
