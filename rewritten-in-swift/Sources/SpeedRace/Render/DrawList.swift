import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the drawing primitives and their painter-order use in src/gfx.rs.
//
// The Rust renderer is an immediate-mode stream of `draw_rectangle`,
// `draw_rectangle_ex`, `draw_circle`, `draw_ellipse`, `draw_circle_lines`,
// `draw_line`, `draw_triangle` and `draw_texture_ex` calls. Their order *is*
// the painter's algorithm. The port records exactly that stream — one Swift
// call per Rust draw call, in the same sequence — and Metal replays it. No
// batching re-orders anything (docs/DECISIONS.md P-0003).
//
// Every primitive becomes an instance of the same six-vertex unit quad whose
// coverage is computed from an analytic signed-distance function (see
// Shaders.metal). Textured quads and the CRT need a different data path, so
// the list tracks draw order with per-kind sub-passes flushed in order.

/// RGBA colour in 0...1, the representation macroquad used.
public struct RGBAColor: Sendable, Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `rgb(r, g, b)` from gfx.rs.
    public static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> RGBAColor {
        RGBAColor(r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0, a: 1.0)
    }

    /// `rgba(r, g, b, a)` from gfx.rs.
    public static func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: Float) -> RGBAColor {
        RGBAColor(r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0, a: a)
    }

    /// `with_alpha(color, a)` from gfx.rs: replace the alpha, keep RGB.
    public func withAlpha(_ alpha: Float) -> RGBAColor {
        var copy = self
        copy.a = alpha
        return copy
    }
}

public struct Point2: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
}

// MARK: - GPU instance layout

/// Shape selector shared with Shaders.metal `PrimitiveInstance.shape`.
public enum ShapeKind: Float, Sendable {
    case rectangle = 0
    case ellipse = 1
    case line = 2
    /// Circle outline: `halfWidth` is the radius, `halfHeight` the thickness.
    case ring = 3
}

/// One instance of the primitive pipeline. Field order, count (16 floats =
/// 64 bytes) and meaning are locked to `PrimitiveInstance` in Shaders.metal;
/// the Metal renderer asserts the stride at startup.
public struct PrimitiveInstance: Sendable {
    public var centerX: Float = 0
    public var centerY: Float = 0
    public var halfWidth: Float = 0
    public var halfHeight: Float = 0
    public var axisX: Float = 1
    public var axisY: Float = 0
    public var r: Float = 0
    public var g: Float = 0
    public var b: Float = 0
    public var a: Float = 0
    public var uvOriginX: Float = 0
    public var uvOriginY: Float = 0
    public var uvWidth: Float = 0
    public var uvHeight: Float = 0
    public var shape: Float = 0
    public var aaScale: Float = 1

    public static let floatCount = 16

    public init() {}
}

/// Vertex for the triangle pipeline (8 floats = 32 bytes): destination
/// position in pixels with a y-down origin, plus colour. Matches
/// `TriangleVertex` in Shaders.metal.
public struct TriangleVertex: Sendable {
    public var x: Float
    public var y: Float
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    // Padding keeps the stride at 32 bytes on both sides.
    public var pad0: Float = 0
    public var pad1: Float = 0

    public init(_ point: Point2, _ color: RGBAColor) {
        x = point.x
        y = point.y
        r = color.r
        g = color.g
        b = color.b
        a = color.a
    }
}

/// A command in the frame's draw list: either a batch of primitives to draw
/// with the primitive pipeline, or a triangle run that must interleave with
/// them in recording order.
public enum DrawCommand: Sendable {
    case primitives(ArraySlice<PrimitiveInstance>)
    case triangles(ArraySlice<TriangleVertex>)
    case texture(rect: (Float, Float, Float, Float))
}

/// Records one surface per frame — the 240 x 360 CRT scene or the 960 x 720
/// cabinet. Commands are flushed into order-preserving batches so textured
/// and untextured work can interleave without reordering.
public final class DrawList {
    /// Draw-list pixels are 240-wide units on the CRT and 960-wide units on
    /// the cabinet; the shader needs the destination scale for anti-aliasing.
    public let aaScale: Float

    public private(set) var commands: [DrawCommand] = []
    private var primitiveScratch: [PrimitiveInstance] = []
    private var triangleScratch: [TriangleVertex] = []

    public init(aaScale: Float, capacity: Int = 8192) {
        self.aaScale = aaScale
        primitiveScratch.reserveCapacity(capacity)
        triangleScratch.reserveCapacity(2048)
    }

    /// Appends a pre-built instance unchanged (investigation scaffolding).
    func recordRaw(_ instance: PrimitiveInstance) {
        appendPrimitive(instance)
    }

    /// Resets the list for a new frame. Called by the renderer after encoding.
    public func begin() {
        commands.removeAll(keepingCapacity: true)
        primitiveScratch.removeAll(keepingCapacity: true)
        triangleScratch.removeAll(keepingCapacity: true)
    }

    public var isEmpty: Bool { primitiveScratch.isEmpty && triangleScratch.isEmpty }

    // MARK: - Rust primitive equivalents

    /// `draw_rectangle(x, y, w, h, color)`.
    ///
    /// macroquad treats w/h as final dimensions; a rectangle is drawn even for
    /// sub-pixel sizes, which the road and scanline code relies on.
    public func rectangle(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: RGBAColor) {
        guard w > 0, h > 0, color.a > 0 else { return }
        var instance = PrimitiveInstance()
        instance.centerX = x + w * 0.5
        instance.centerY = y + h * 0.5
        instance.halfWidth = max(w * 0.5, 0.0001)
        instance.halfHeight = max(h * 0.5, 0.0001)
        instance.shape = ShapeKind.rectangle.rawValue
        instance.aaScale = aaScale
        writeColor(color, into: &instance)
        appendPrimitive(instance)
    }

    /// `draw_rectangle_ex` with offset (0.5, 0.5): a rect rotated about its
    /// own centre. Used by `draw_car` for every car panel.
    public func rotatedRectangle(
        centerX: Float, centerY: Float, width: Float, height: Float, rotation: Float,
        _ color: RGBAColor
    ) {
        guard width > 0, height > 0, color.a > 0 else { return }
        var instance = PrimitiveInstance()
        instance.centerX = centerX
        instance.centerY = centerY
        instance.halfWidth = max(width * 0.5, 0.0001)
        instance.halfHeight = max(height * 0.5, 0.0001)
        instance.axisX = rustCos(rotation)
        instance.axisY = rustSin(rotation)
        instance.shape = ShapeKind.rectangle.rawValue
        instance.aaScale = aaScale
        // Rotated boxes need a slightly bigger local-space slop than
        // axis-aligned ones; the shader scales by the box's shorter side.
        writeColor(color, into: &instance)
        appendPrimitive(instance)
    }

    /// `draw_rectangle_lines(x, y, w, h, 1.0, color)` and the thicker variant
    /// used by the rasterised font (`thickness` there is the text scale).
    ///
    /// macroquad strokes rectangles as four quads of the given thickness,
    /// extended half a thickness past each corner. That decomposition is
    /// reproduced exactly, so long straight edges of the cabinet frame match
    /// pixel for pixel. Divergence D-0008 documents the rounded-corner
    /// simplification.
    public func rectangleLines(
        _ x: Float, _ y: Float, _ w: Float, _ h: Float, thickness: Float, _ color: RGBAColor
    ) {
        guard w > 0, h > 0, thickness > 0, color.a > 0 else { return }
        let t = thickness
        let half = t * 0.5
        rectangle(x - half, y - half, w + t, t, color)  // top
        rectangle(x - half, y + h - half, w + t, t, color)  // bottom
        rectangle(x - half, y + half, t, h - t, color)  // left
        rectangle(x + w - half, y + half, t, h - t, color)  // right
    }

    /// `draw_circle(cx, cy, radius, color)`.
    public func circle(_ cx: Float, _ cy: Float, _ radius: Float, _ color: RGBAColor) {
        ellipse(cx, cy, radius, radius, rotation: 0, color)
    }

    /// `draw_ellipse(cx, cy, rx, ry, rotation, color)`.
    public func ellipse(
        _ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, rotation: Float, _ color: RGBAColor
    ) {
        guard rx > 0, ry > 0, color.a > 0 else { return }
        var instance = PrimitiveInstance()
        instance.centerX = cx
        instance.centerY = cy
        instance.halfWidth = rx
        instance.halfHeight = ry
        instance.axisX = rustCos(rotation)
        instance.axisY = rustSin(rotation)
        instance.shape = ShapeKind.ellipse.rawValue
        instance.aaScale = aaScale
        writeColor(color, into: &instance)
        appendPrimitive(instance)
    }

    /// `draw_circle_lines(cx, cy, radius, thickness, color)`, used for the
    /// speedometer's bezel and inner ring.
    ///
    /// macroquad approximates the ring with many short quads. The port records
    /// a `ring` primitive (radius plus thickness) and tessellates it on the
    /// CPU into a triangle strip, so the outline stays smooth at the 1.5x CRT
    /// scale (D-0006).
    public func circleLines(
        _ cx: Float, _ cy: Float, _ radius: Float, _ thickness: Float, _ color: RGBAColor
    ) {
        guard radius > 0, thickness > 0, color.a > 0 else { return }
        var instance = PrimitiveInstance()
        instance.centerX = cx
        instance.centerY = cy
        instance.halfWidth = radius
        instance.halfHeight = thickness
        instance.shape = ShapeKind.ring.rawValue
        instance.aaScale = aaScale
        writeColor(color, into: &instance)
        appendPrimitive(instance)
    }

    /// `draw_line(x1, y1, x2, y2, thickness, color)`.
    public func line(
        _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ thickness: Float, _ color: RGBAColor
    ) {
        let dx = x2 - x1
        let dy = y2 - y1
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0, thickness > 0, color.a > 0 else { return }
        var instance = PrimitiveInstance()
        instance.centerX = (x1 + x2) * 0.5
        instance.centerY = (y1 + y2) * 0.5
        instance.halfWidth = length * 0.5
        instance.halfHeight = thickness * 0.5
        instance.axisX = dx / length
        instance.axisY = dy / length
        instance.shape = ShapeKind.line.rawValue
        instance.aaScale = aaScale
        writeColor(color, into: &instance)
        appendPrimitive(instance)
    }

    /// `fill_quad(a, b, c, d, color)` from gfx.rs: two `draw_triangle` calls.
    /// Rendered through the triangle pipeline with exact vertices.
    public func quad(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2, _ color: RGBAColor) {
        guard color.a > 0 else { return }
        triangleScratch.append(TriangleVertex(a, color))
        triangleScratch.append(TriangleVertex(b, color))
        triangleScratch.append(TriangleVertex(c, color))
        triangleScratch.append(TriangleVertex(a, color))
        triangleScratch.append(TriangleVertex(c, color))
        triangleScratch.append(TriangleVertex(d, color))
    }

    /// `draw_texture_ex(screen, x, y, WHITE, dest_size, flip_y: true)` for the
    /// CRT. The port stores the target rectangle; the renderer samples the
    /// offscreen texture upright (D-0007).
    public func texture(x: Float, y: Float, width: Float, height: Float) {
        guard width > 0, height > 0 else { return }
        flushTriangles()
        if !primitiveScratch.isEmpty {
            commands.append(.primitives(primitiveScratch[...]))
            primitiveScratch.removeAll(keepingCapacity: true)
        }
        commands.append(.texture(rect: (x, y, width, height)))
    }

    /// Ends recording; flushes any tail batches into `commands`.
    public func finalize() {
        if !triangleScratch.isEmpty || !primitiveScratch.isEmpty {
            flushTriangles()
            if !primitiveScratch.isEmpty {
                commands.append(.primitives(primitiveScratch[...]))
                primitiveScratch.removeAll(keepingCapacity: true)
            }
        }
    }

    // MARK: - Internals

    /// Appends one primitive, flushing any pending triangles first so the
    /// recorded order is preserved exactly.
    ///
    /// Without this, triangles were only flushed at `finalize()`, which put the
    /// road *after* the CRT overlay text and drew the road over the title
    /// (docs/INVESTIGATION-renderer.md).
    private func appendPrimitive(_ instance: PrimitiveInstance) {
        if !triangleScratch.isEmpty {
            flushTriangles()
        }
        primitiveScratch.append(instance)
    }

    /// Painter order: triangles and primitives interleave, so whichever run
    /// was recorded first must be flushed first.
    private func flushTriangles() {
        guard !triangleScratch.isEmpty else { return }
        if !primitiveScratch.isEmpty {
            commands.append(.primitives(primitiveScratch[...]))
            primitiveScratch.removeAll(keepingCapacity: true)
        }
        commands.append(.triangles(triangleScratch[...]))
        triangleScratch.removeAll(keepingCapacity: true)
    }

    private func writeColor(
        _ color: RGBAColor, into instance: inout PrimitiveInstance
    ) {
        instance.r = color.r
        instance.g = color.g
        instance.b = color.b
        instance.a = color.a
    }
}
