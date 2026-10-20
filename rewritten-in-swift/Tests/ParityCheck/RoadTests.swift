import Foundation
import SpeedRace

// PORT OF: the `#[cfg(test)]` module in src/road.rs.

let roadTests: [TestCase] = [
    TestCase("road::projection_gets_higher_and_smaller_with_distance") {
        let near = Road.project(0.0)
        let mid = Road.project(400.0)
        let far = Road.project(Road.viewDistance)
        try expect(abs(near.y - Road.bottomY) < 0.001, "near slice should sit at the bottom")
        try expect(mid.y < near.y && far.y < mid.y, "y must rise towards the horizon")
        try expect(far.y > Road.horizonY, "far slice must stay below the horizon")
        try expect(mid.scale < near.scale && far.scale < mid.scale, "scale must shrink")
    },
    TestCase("road::road_curves_are_smooth_and_bounded") {
        var previous = Road.center(0.0)
        var maxStep: Float = 0.0
        for i in 1..<20_000 {
            let value = Road.center(Float(i) * 0.5)
            maxStep = max(maxStep, abs(value - previous))
            previous = value
        }
        // A half-unit step must never jump more than a pixel or two, otherwise
        // the polygonal road would visibly tear.
        try expect(maxStep < 1.0, "road jumped by \(maxStep)")
    },
    TestCase("road::relative_offset_starts_at_zero") {
        for d: Float in [0.0, 123.0, 9_999.0] {
            try expect(abs(Road.screenOffset(distance: d, z: 0.0)) < 0.001, "offset at \(d)")
        }
    },
]
