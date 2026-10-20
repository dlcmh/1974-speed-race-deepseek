import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// CPU triangulation of the draw list into one flat vertex buffer per frame.
//
// Why: the working Pac-Man port (docs/METAL-VS-PACMAN.md) triangulates on the
// CPU and submits a single draw call, and it renders reliably on this machine
// where an instanced-quad + SDF pipeline did not. This replaces ADR P-0005.
//
// The vertex format is six floats per vertex in two groups, packed exactly as
// `VertexIn` in MetalShaderSource:
//     x, y, r, g, b, a, u, v      (8 floats = 32 bytes)
//
// Textured vertices are only emitted by `texture(...)`; everything else gets a
// uv of (0, 0) and is drawn by the solid pipeline, so the two never mix in one
// buffer range.

/// One vertex: destination pixels (y down), straight-alpha colour, texture uv.
public struct CanvasVertex {
    public var x: Float
    public var y: Float
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    public var u: Float
    public var v: Float

    public static let floatCount = 8
    public static let stride = floatCount * MemoryLayout<Float>.stride
}

/// Accumulates triangles for one render pass.
public final class VertexCanvas {
    public private(set) var vertices: [CanvasVertex] = []
    /// One draw call: a contiguous vertex range and which pipeline draws it.
    public struct Segment {
        public var range: Range<Int>
        public var textured: Bool
    }

    /// Contiguous runs in recording order. Solid and textured geometry can
    /// interleave (the cabinet draws the CRT blit and *then* the control deck),
    /// so the pipeline is switched per segment rather than assumed.
    public private(set) var segments: [Segment] = []
    private var lastWasTextured = false

    public init(reserveVertices: Int = 60_000) {
        vertices.reserveCapacity(reserveVertices)
    }

    public func reset() {
        vertices.removeAll(keepingCapacity: true)
        segments.removeAll(keepingCapacity: true)
        lastWasTextured = false
    }

    /// Starts (or extends) a solid run.
    private func beginSolid() {
        if lastWasTextured || segments.isEmpty {
            segments.append(Segment(range: vertices.count..<vertices.count, textured: false))
            lastWasTextured = false
        }
    }

    /// Extends the current segment to cover the vertices just appended.
    private func closeSegment() {
        guard !segments.isEmpty else { return }
        let start = segments[segments.count - 1].range.lowerBound
        segments[segments.count - 1].range = start..<vertices.count
    }

    public var isEmpty: Bool { vertices.isEmpty }

    // MARK: - Low-level emitters

    private func vertex(
        _ x: Float, _ y: Float, _ color: RGBAColor, _ u: Float = 0, _ v: Float = 0
    ) -> CanvasVertex {
        CanvasVertex(x: x, y: y, r: color.r, g: color.g, b: color.b, a: color.a, u: u, v: v)
    }

    /// Appends a triangle, skipping fully transparent ones.
    public func triangle(
        _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float, _ cx: Float, _ cy: Float,
        _ color: RGBAColor
    ) {
        guard color.a > 0 else { return }
        beginSolid()
        vertices.append(vertex(ax, ay, color))
        vertices.append(vertex(bx, by, color))
        vertices.append(vertex(cx, cy, color))
        closeSegment()
    }

    /// Appends a convex quad as two triangles (a-b-c, a-c-d), the same split as
    /// `fill_quad` in the canonical gfx.rs.
    public func quad(
        _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float,
        _ cx: Float, _ cy: Float, _ dx: Float, _ dy: Float, _ color: RGBAColor
    ) {
        guard color.a > 0 else { return }
        beginSolid()
        vertices.append(vertex(ax, ay, color))
        vertices.append(vertex(bx, by, color))
        vertices.append(vertex(cx, cy, color))
        vertices.append(vertex(ax, ay, color))
        vertices.append(vertex(cx, cy, color))
        vertices.append(vertex(dx, dy, color))
        closeSegment()
    }

    // MARK: - Shapes

    /// Axis-aligned or rotated rectangle, described by four corners.
    public func rectangle(
        centerX: Float, centerY: Float, halfWidth: Float, halfHeight: Float,
        axisX: Float, axisY: Float, _ color: RGBAColor
    ) {
        guard halfWidth > 0, halfHeight > 0, color.a > 0 else { return }
        // Perpendicular to the axis, matching the primitive shader's layout.
        let alongX = axisY
        let alongY = -axisX
        func corner(_ sx: Float, _ sy: Float) -> (Float, Float) {
            let ox = sx * halfWidth
            let oy = sy * halfHeight
            return (centerX + axisX * ox + alongX * oy, centerY + axisY * ox + alongY * oy)
        }
        let (x0, y0) = corner(-1, -1)
        let (x1, y1) = corner(1, -1)
        let (x2, y2) = corner(1, 1)
        let (x3, y3) = corner(-1, 1)
        quad(x0, y0, x1, y1, x2, y2, x3, y3, color)
    }

    /// Ellipse as a triangle fan. 32 segments matches macroquad's tessellation
    /// closely enough that the 240 x 360 output is indistinguishable.
    public func ellipse(
        centerX: Float, centerY: Float, radiusX: Float, radiusY: Float, rotation: Float,
        _ color: RGBAColor
    ) {
        guard radiusX > 0, radiusY > 0, color.a > 0 else { return }
        let segments = 32
        let cosR = rustCos(rotation)
        let sinR = rustSin(rotation)
        let step = Float.tau / Float(segments)
        var previousX = 0 as Float
        var previousY = 0 as Float
        for index in 0...segments {
            let angle = Float(index) * step
            let ex = rustCos(angle) * radiusX
            let ey = rustSin(angle) * radiusY
            let px = centerX + ex * cosR - ey * sinR
            let py = centerY + ex * sinR + ey * cosR
            if index > 0 {
                beginSolid()
                vertices.append(vertex(centerX, centerY, color))
                vertices.append(vertex(previousX, previousY, color))
                vertices.append(vertex(px, py, color))
                closeSegment()
            }
            previousX = px
            previousY = py
        }
    }

    /// Ring (circle outline) as a triangle strip of quads.
    public func ring(
        centerX: Float, centerY: Float, radius: Float, thickness: Float, _ color: RGBAColor
    ) {
        guard radius > 0, thickness > 0, color.a > 0 else { return }
        let segments = 40
        let inner = max(radius - thickness * 0.5, 0.0001)
        let outer = radius + thickness * 0.5
        let step = Float.tau / Float(segments)
        var previousInner = (inner, 0 as Float)
        var previousOuter = (outer, 0 as Float)
        for index in 0...segments {
            let angle = Float(index) * step
            let c = rustCos(angle)
            let s = rustSin(angle)
            let i = (centerX + c * inner, centerY + s * inner)
            let o = (centerX + c * outer, centerY + s * outer)
            if index > 0 {
                quad(
                    previousInner.0, previousInner.1, previousOuter.0, previousOuter.1,
                    o.0, o.1, i.0, i.1, color)
            }
            previousInner = i
            previousOuter = o
        }
    }

    /// Line segment as a quad with square caps (macroquad's `draw_line`).
    public func line(
        _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, thickness: Float,
        _ color: RGBAColor
    ) {
        let dx = x1 - x0
        let dy = y1 - y0
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001, thickness > 0, color.a > 0 else { return }
        let ux = dx / length
        let uy = dy / length
        let half = thickness * 0.5
        let nx = -uy * half
        let ny = ux * half
        quad(
            x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, color)
    }

    /// Textured quad; recorded as its own draw range.
    public func texture(
        _ x: Float, _ y: Float, _ width: Float, _ height: Float, _ color: RGBAColor
    ) {
        guard width > 0, height > 0 else { return }
        let start = vertices.count
        segments.append(Segment(range: start..<start, textured: true))
        lastWasTextured = true
        let x1 = x + width
        let y1 = y + height
        // uv (0,0) is the top-left of the texture, matching the y-down draw list.
        vertices.append(vertex(x, y, color, 0, 0))
        vertices.append(vertex(x1, y, color, 1, 0))
        vertices.append(vertex(x1, y1, color, 1, 1))
        vertices.append(vertex(x, y, color, 0, 0))
        vertices.append(vertex(x1, y1, color, 1, 1))
        vertices.append(vertex(x, y1, color, 0, 1))
        segments[segments.count - 1].range = start..<vertices.count
    }
}

extension Float {
    /// TAU with Rust's bit pattern (see `rustTau` in RustMath.swift).
    public static var tau: Float { rustTau }
}
