// Speed Race (1974) — Swift + Metal port.
//
// Temporary smoke executable used while the windowed app is being built.
// It exercises the ported simulation and renderer without opening a window:
//
//   swift run speed-race            # simulate one minute and print state
//
// Replaced by the AppKit/Metal app target. Kept separate from the library so
// the library itself never declares a `main` (that would break the
// `parity-check` executable, which links the same module).

import Foundation
import SpeedRace

let game = Game(best: 0, seed: 1974)
game.startRace()
var steps = 0
while steps < 4000 {
    game.update(controls: Controls(steer: 0.2, throttle: 1.0, brake: 0.0), dt: 1.0 / 60.0)
    steps += 1
    if game.phase == .gameOver { break }
}
print("steps=\(steps) phase=\(game.phase) score=\(game.score) timeLeft=\(game.timeLeft)")
print("road center(1000)=\(Road.center(1000)) project(400)=\(Road.project(400))")
