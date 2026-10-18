//! The endless road: a cheap pseudo-3D projection plus a hand-tuned,
//! deterministic centre line. Nothing here knows about cars or scores.

/// How far down the road the player can see, in world units.
pub const VIEW_DISTANCE: f32 = 1_600.0;

/// Screen space (the 240 x 360 internal canvas) occupied by the road.
pub const HORIZON_Y: f32 = 76.0;
pub const BOTTOM_Y: f32 = 360.0;

/// Half-width of the road at the bottom of the screen.
pub const ROAD_HALF_WIDTH: f32 = 112.0;

/// A point on the road, projected to the low-resolution canvas.
#[derive(Clone, Copy, Debug)]
pub struct Projection {
    /// Screen y of the slice.
    pub y: f32,
    /// Perspective scale: 1.0 at the camera, approaching 0 at the horizon.
    pub scale: f32,
}

/// Project a distance in front of the camera onto the screen.
///
/// The 240-unit focal length gives a tight, slightly theatrical perspective
/// that suits a 1974 upright cabinet.
pub fn project(z: f32) -> Projection {
    let z = z.max(0.0);
    let scale = 260.0 / (260.0 + z);
    Projection {
        y: HORIZON_Y + (BOTTOM_Y - HORIZON_Y) * scale,
        scale,
    }
}

/// Lateral position of the road centre at a distance along the track.
///
/// Three incommensurate sine waves produce long sweepers, medium bends and a
/// subtle wiggle without ever repeating in a way the player can memorise.
pub fn center(distance: f32) -> f32 {
    150.0 * (distance * 0.001_15).sin()
        + 82.0 * (distance * 0.002_65 + 1.1).sin()
        + 26.0 * (distance * 0.006_10 + 0.4).sin()
}

/// First derivative of [`center`], by central difference.
pub fn tangent(distance: f32) -> f32 {
    let h = 1.5;
    (center(distance + h) - center(distance - h)) / (2.0 * h)
}

/// Second derivative of [`center`], by central difference.
///
/// Positive values mean the road is bending to the right.
pub fn curvature(distance: f32) -> f32 {
    let h = 10.0;
    (center(distance + h) - 2.0 * center(distance) + center(distance - h)) / (h * h)
}

/// Screen-space lateral offset of a slice `z` ahead of the camera.
///
/// The tangent term removes the constant heading of the curve, so a long,
/// constant bend sits diagonally rather than sweeping off screen.
pub fn screen_offset(distance: f32, z: f32) -> f32 {
    (center(distance + z) - center(distance) - tangent(distance) * z) * 0.92
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn projection_gets_higher_and_smaller_with_distance() {
        let near = project(0.0);
        let mid = project(400.0);
        let far = project(VIEW_DISTANCE);
        assert!((near.y - BOTTOM_Y).abs() < 0.001);
        assert!(mid.y < near.y && far.y < mid.y);
        assert!(far.y > HORIZON_Y);
        assert!(mid.scale < near.scale && far.scale < mid.scale);
    }

    #[test]
    fn road_curves_are_smooth_and_bounded() {
        let mut previous = center(0.0);
        let mut max_step: f32 = 0.0;
        for i in 1..20_000 {
            let value = center(i as f32 * 0.5);
            max_step = max_step.max((value - previous).abs());
            previous = value;
        }
        // A half-unit step must never jump more than a pixel or two, otherwise
        // the polygonal road would visibly tear.
        assert!(max_step < 1.0, "road jumped by {max_step}");
    }

    #[test]
    fn relative_offset_starts_at_zero() {
        for d in [0.0, 123.0, 9_999.0] {
            assert!(screen_offset(d, 0.0).abs() < 0.001);
        }
    }
}
