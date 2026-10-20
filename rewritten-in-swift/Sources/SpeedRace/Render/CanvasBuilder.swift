import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// Converts a `DrawList` (the recorded Rust draw calls) into `VertexCanvas`
// triangles. One function per Rust primitive, mirroring `gfx.rs` call for call.
//
// This is the CPU half of the rendering path adopted from the working Pac-Man
// port (docs/METAL-VS-PACMAN.md): the draw list stays as the reviewable record
// of what the Rust renderer did, and this file turns it into geometry.

public enum CanvasBuilder {
    public static func build(_ list: DrawList, into canvas: VertexCanvas) {
        list.finalize()
        // Replay in recording order so painter order is preserved.
        for command in list.commands {
            switch command {
            case .primitives(let instances):
                for instance in instances {
                    emit(instance, into: canvas)
                }
            case .triangles(let vertices):
                // Already exact triangles; convert straight across.
                var index = vertices.startIndex
                while index + 2 < vertices.endIndex {
                    let a = vertices[index]
                    let b = vertices[index + 1]
                    let c = vertices[index + 2]
                    let color = RGBAColor(r: a.r, g: a.g, b: a.b, a: a.a)
                    canvas.triangle(a.x, a.y, b.x, b.y, c.x, c.y, color)
                    index += 3
                }
            case .texture(let rect):
                canvas.texture(rect.0, rect.1, rect.2, rect.3, RGBAColor(r: 1, g: 1, b: 1))
            }
        }
    }

    /// Emits one recorded primitive. `shape` selects rectangle, ellipse or line;
    /// the `aaScale` field is not needed on this path because the CPU
    /// tessellation is already smooth.
    private static func emit(_ instance: PrimitiveInstance, into canvas: VertexCanvas) {
        let color = RGBAColor(
            r: instance.r, g: instance.g, b: instance.b, a: instance.a)
        switch instance.shape {
        case ShapeKind.ring.rawValue:
            canvas.ring(
                centerX: instance.centerX, centerY: instance.centerY,
                radius: instance.halfWidth, thickness: instance.halfHeight, color)
        case ShapeKind.ellipse.rawValue:
            let rotation = atan2(instance.axisY, instance.axisX)
            canvas.ellipse(
                centerX: instance.centerX, centerY: instance.centerY,
                radiusX: instance.halfWidth, radiusY: instance.halfHeight,
                rotation: rotation, color)
        case ShapeKind.line.rawValue:
            // A capsule of length 2*halfWidth and thickness 2*halfHeight.
            let length = instance.halfWidth
            let ux = instance.axisX
            let uy = instance.axisY
            canvas.line(
                instance.centerX - ux * length, instance.centerY - uy * length,
                instance.centerX + ux * length, instance.centerY + uy * length,
                thickness: instance.halfHeight * 2, color)
        default:
            canvas.rectangle(
                centerX: instance.centerX, centerY: instance.centerY,
                halfWidth: instance.halfWidth, halfHeight: instance.halfHeight,
                axisX: instance.axisX, axisY: instance.axisY, color)
        }
    }
}
