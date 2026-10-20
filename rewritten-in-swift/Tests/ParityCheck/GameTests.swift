import Foundation
import SpeedRace

// PORT OF: the `#[cfg(test)]` module in src/game.rs, plus the extra checks the
// port adds (marked "port:"), each of which pins a Rust behaviour whose Swift
// translation is easy to get subtly wrong.

private func advance(_ game: Game, seconds: Float) {
    let steps = Int((seconds / 0.016).rounded(.up))
    for _ in 0..<steps {
        game.update(controls: Controls(throttle: 1.0), dt: 0.016)
    }
}

let gameTests: [TestCase] = [
    TestCase("game::countdown_hands_over_to_the_timer") {
        let game = Game(best: 0, seed: 1974)
        game.startRace()
        try expectEqual(game.phase, .countdown, "phase after start")
        advance(game, seconds: 3.1)
        try expectEqual(game.phase, .racing, "phase after countdown")
        try expect(game.timeLeft < Game.startTime, "timer should have started")
        try expect(game.timeLeft > Game.startTime - 1.0, "timer should be near 90 s")
    },
    TestCase("game::timer_expiry_ends_the_run_and_records_a_best") {
        let game = Game(best: 0, seed: 7)
        game.startRace()
        game.forcePhase(.racing)  // test hook mirroring Rust's direct field write
        game.score = 4321
        game.timeLeft = 0.01
        game.update(controls: Controls.idle, dt: 0.02)
        try expectEqual(game.phase, .gameOver, "phase")
        try expectEqual(game.best, 4321, "best")
        try expect(game.newBest, "new best flag")
        try expect(game.bestDirty, "best dirty flag")
        try expect(game.takeEvents().contains(.gameOver), "GameOver event")
    },
    TestCase("game::overtaking_awards_points_based_on_speed") {
        let game = Game(best: 0, seed: 12)
        game.startRace()
        game.forcePhase(.racing)
        game.speed = 180.0
        game.traffic.removeAll()
        game.traffic.append(
            TrafficCar(z: Game.playerZ - 20.0, lateral: 0.66, speed: 40.0, kind: 0, variant: 0))
        game.update(controls: Controls.idle, dt: 0.016)
        try expect(game.score >= 150, "score \(game.score)")
        try expect(game.takeEvents().contains(.overtake), "Overtake event")
    },
    TestCase("game::a_car_in_your_lane_causes_a_crash_and_then_a_restart") {
        let game = Game(best: 0, seed: 99)
        game.startRace()
        game.forcePhase(.racing)
        game.speed = 120.0
        game.traffic.removeAll()
        game.traffic.append(
            TrafficCar(z: Game.playerZ, lateral: 0.0, speed: 110.0, kind: 1, variant: 1))
        game.update(controls: Controls.idle, dt: 0.016)
        try expectEqual(game.phase, .crashed, "phase after collision")
        try expect(game.takeEvents().contains(.crash), "Crash event")
        let timerBefore = game.timeLeft
        advance(game, seconds: 1.6)
        try expectEqual(game.phase, .racing, "phase after restart")
        try expect(game.timeLeft <= timerBefore, "clock keeps running through a crash")
        try expect(game.traffic.count >= 4, "track reseeded with traffic")
    },
    TestCase("game::reaching_the_extend_threshold_adds_time") {
        let game = Game(best: 0, seed: 5)
        game.startRace()
        game.forcePhase(.racing)
        game.timeLeft = 30.0
        game.score = 1000
        game.nextExtend = 1000
        game.updateExtensionsForTest()
        try expect(game.timeLeft >= 49.9, "time extended to \(game.timeLeft)")
        try expect(game.nextExtend > 1000, "next threshold advanced")
        try expect(game.takeEvents().contains(.extend), "Extend event")
    },
    TestCase("game::steering_can_reach_both_edges_but_never_leaves_the_road") {
        let game = Game(best: 0, seed: 3)
        game.startRace()
        game.forcePhase(.racing)
        game.timeLeft = 60.0
        game.speed = 160.0
        for _ in 0..<400 {
            game.update(controls: Controls(steer: -1.0, throttle: 1.0), dt: 0.016)
        }
        try expect(game.lateral >= -Game.playerLateralLimit - 0.001, "left edge held")
        for _ in 0..<400 {
            game.update(controls: Controls(steer: 1.0, throttle: 1.0), dt: 0.016)
        }
        try expect(game.lateral <= Game.playerLateralLimit + 0.001, "right edge held")
    },

    // Port-specific checks.

    TestCase("port: paused_game_ignores_input_but_still_tracks_controls") {
        let game = Game(best: 0, seed: 21)
        game.startRace()
        game.forcePhase(.racing)
        game.togglePause()
        try expect(game.paused, "togglePause should pause a race")
        let speedBefore = game.speed
        game.update(controls: Controls(steer: 1.0, throttle: 1.0), dt: 1.0)
        try expectEqual(game.speed, speedBefore, "speed frozen while paused")
        try expectEqual(game.controls.throttle, 1.0, "controls snapshot still updated")
        game.update(controls: Controls.idle, dt: 1.0 / 60.0)
        try expectEqual(game.timeLeft, Game.startTime, "clock frozen while paused")
    },
    TestCase("port: pause_is_ignored_on_attract_and_game_over") {
        let game = Game(best: 0, seed: 22)
        game.togglePause()
        try expect(!game.paused, "attract cannot be paused")
        game.forcePhase(.gameOver)
        game.togglePause()
        try expect(!game.paused, "game over cannot be paused")
    },
    TestCase("port: spawn_never_forms_an_unavoidable_wall") {
        // Drives the real spawner for a long race and checks the invariant the
        // Rust comment promises: never four cars within one lane-width at the
        // same depth. Runs on a seeded RNG so it is deterministic.
        let game = Game(best: 0, seed: 1974)
        game.startRace()
        game.forcePhase(.racing)
        for _ in 0..<60 * 120 {
            game.update(controls: Controls(throttle: 1.0), dt: 1.0 / 60.0)
            _ = game.takeEvents()
            let cars = game.traffic
            for i in cars.indices {
                var neighbours = 0
                for j in cars.indices where j != i {
                    if abs(cars[i].z - cars[j].z) < 130.0 && abs(cars[i].lateral - cars[j].lateral) < 0.24 {
                        neighbours += 1
                    }
                }
                try expect(neighbours < 3, "four-car wall at z=\(cars[i].z)")
            }
            if game.phase == .gameOver { break }
        }
    },
    TestCase("port: thirty_six_hundred_frames_are_deterministic") {
        // Same seed, same inputs, same bit-exact state — the property the
        // golden trace fixtures depend on.
        func run() -> [UInt32] {
            let game = Game(best: 0, seed: 0x5EED_1974)
            game.startRace()
            var bits: [UInt32] = []
            for frame in 0..<3_600 {
                let steer: Float = frame % 120 < 60 ? -0.6 : 0.6
                game.update(controls: Controls(steer: steer, throttle: 1.0), dt: 1.0 / 60.0)
                _ = game.takeEvents()
                bits.append(game.speed.bitPattern)
                bits.append(game.lateral.bitPattern)
                bits.append(game.distance.bitPattern)
                bits.append(game.timeLeft.bitPattern)
                bits.append(game.score)
                bits.append(UInt32(game.traffic.count))
            }
            return bits
        }
        try expectEqual(run(), run(), "seeded runs must be identical")
    },
    TestCase("port: time_extensions_compound_like_rust") {
        // Rust: next_extend = next_extend + 1500 + extension_count * 500,
        // applying `extension_count` *after* incrementing it.
        let game = Game(best: 0, seed: 77)
        game.startRace()
        game.forcePhase(.racing)
        game.timeLeft = 1.0
        game.score = 2000
        game.nextExtend = 1000
        game.updateExtensionsForTest()
        // First award: next = 1000 + 1500 + 1*500 = 3000 (2000 < 3000, stop).
        try expectEqual(game.extensionCount, 1, "one extension awarded")
        try expectEqual(game.nextExtend, 3000, "second threshold")
        try expect(abs(game.timeLeft - 21.0) < 0.001, "timer \(game.timeLeft)")
        // A score jump large enough to cross several thresholds at once.
        game.score = 10_000
        game.updateExtensionsForTest()
        // 3000 -> 3000+1500+2*500 = 5500 -> 5500+1500+3*500 = 8500 -> 8500+1500+4*500 = 12000
        try expectEqual(game.extensionCount, 4, "extensions catch up to the score")
        try expectEqual(game.nextExtend, 12_000, "compounded thresholds")
        try expect(abs(game.timeLeft - 81.0) < 0.001, "timer \(game.timeLeft)")
    },
]
