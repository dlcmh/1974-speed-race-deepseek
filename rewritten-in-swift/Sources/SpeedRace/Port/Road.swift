// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/road.rs (canonical Rust game, repository root).
//
// The endless road: a cheap pseudo-3D projection plus a hand-tuned,
// deterministic centre line. Nothing here knows about cars or scores.
//
// Floating point note (docs/INVESTIGATION-parity.md): every expression keeps the Rust
// evaluation order and f32 width. Apple silicon evaluates Float operations
// in single precision exactly like Rust on aarch64, so results are
// bit-identical for the same inputs. Double intermediates would not be.
import Foundation

public enum Road {
    /// How far down the road the player can see, in world units.
    public static let viewDistance: Float = 1_600.0

    /// Screen space (the 240 x 360 internal canvas) occupied by the road.
    public static let horizonY: Float = 76.0
    public static let bottomY: Float = 360.0

    /// Half-width of the road at the bottom of the screen.
    public static let roadHalfWidth: Float = 112.0

    /// A point on the road, projected to the low-resolution canvas.
    public struct Projection: Equatable, Sendable {
        /// Screen y of the slice.
        public var y: Float
        /// Perspective scale: 1.0 at the camera, approaching 0 at the horizon.
        public var scale: Float
    }

    /// Project a distance in front of the camera onto the screen.
    ///
    /// The 240-unit focal length gives a tight, slightly theatrical
    /// perspective that suits a 1974 upright cabinet.
    public static func project(_ z: Float) -> Projection {
        let z = max(z, 0.0)
        let scale = 260.0 / (260.0 + z)
        return Projection(y: horizonY + (bottomY - horizonY) * scale, scale: scale)
    }

    /// Lateral position of the road centre at a distance along the track.
    ///
    /// Three incommensurate sine waves produce long sweepers, medium bends
    /// and a subtle wiggle without ever repeating in a way the player can
    /// memorise.
    public static func center(_ distance: Float) -> Float {
        150.0 * rustSinFloat(distance * 0.001_15)
            + 82.0 * rustSinFloat(distance * 0.002_65 + 1.1)
            + 26.0 * rustSinFloat(distance * 0.006_10 + 0.4)
    }

    /// First derivative of `center`, by central difference.
    public static func tangent(_ distance: Float) -> Float {
        let h: Float = 1.5
        return (center(distance + h) - center(distance - h)) / (2.0 * h)
    }

    /// Second derivative of `center`, by central difference.
    ///
    /// Positive values mean the road is bending to the right.
    public static func curvature(_ distance: Float) -> Float {
        let h: Float = 10.0
        return (center(distance + h) - 2.0 * center(distance) + center(distance - h)) / (h * h)
    }

    /// Screen-space lateral offset of a slice `z` ahead of the camera.
    ///
    /// The tangent term removes the constant heading of the curve, so a long,
    /// constant bend sits diagonally rather than sweeping off screen.
    public static func screenOffset(distance: Float, z: Float) -> Float {
        (center(distance + z) - center(distance) - tangent(distance) * z) * 0.92
    }
}
