// Speed Race (1974) — Swift + Metal port.
//
// Headless renderer used for visual verification.
//
//   swift run speed-race --render <title|race|all> [--out <dir>]
//
// Renders the cabinet exactly as the window would (same renderer, same draw
// lists, same CRT texture) but writes PNGs instead of presenting a drawable.
// The output is compared with the canonical Rust screenshots in
// ../../docs/title-screen.png and ../../docs/gameplay.png; see docs/PARITY.md.
//
// This is a development tool, not part of the game: it lives in its own target
// so the app never links a screenshot path that could be left enabled.

import Foundation
import SpeedRace

@main
struct RenderTool {
    static func main() {
        var mode = "all"
        var outDir = FileManager.default.currentDirectoryPath
        var args = CommandLine.arguments.dropFirst()
        while let arg = args.popFirst() {
            switch arg {
            case "--render":
                mode = args.popFirst() ?? "all"
            case "--out":
                outDir = args.popFirst() ?? outDir
            default:
                continue
            }
        }

        do {
            let renderer = try MetalRenderer()
            let scenarios: [(String, Game, Float)]
            switch mode {
            case "title":
                scenarios = [("swift-title-screen", titleGame(), 6.0)]
            case "race":
                scenarios = [("swift-gameplay", raceGame(), 12.0)]
            case "debug-cabinet":
                // Diagnostics for the render investigation.
                debugDump(renderer)
                return
            default:
                scenarios = [("swift-title-screen", titleGame(), 6.0), ("swift-gameplay", raceGame(), 12.0)]
            }
            for (name, game, time) in scenarios {
                let pixels = try renderFrame(renderer: renderer, game: game, time: time, muted: false)
                guard let pixels else { continue }
                let data = PNGEncoder.encodeRGBA(
                    width: pixels.width, height: pixels.height, pixels: pixels.pixels)
                let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
                try data.write(to: url)
                print("wrote \(url.path) (\(pixels.width)x\(pixels.height))")
            }
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Renders just the cabinet (no CRT scene) and just the CRT scene, and
    /// writes both, so the two halves of the composite can be inspected.
    static func debugDump(_ renderer: MetalRenderer) {
        let game = titleGame()
        do {
            for (name, cabinetOnly) in [("swift-cabinet-only", true), ("swift-crt-only", false)] {
                let crt = DrawList(aaScale: 1)
                crt.begin()
                if !cabinetOnly { CrtScene.draw(crt, game: game, time: 6) }
                let cabinet = DrawList(aaScale: 1)
                cabinet.begin()
                cabinet.rectangle(0, 0, 960, 720, RGBAColor.rgb(0, 0, 0))
                if cabinetOnly { Cabinet.draw(cabinet, game: game, muted: false) }
                let pixels = try renderer.render(crt: crt, cabinet: cabinet, drawable: nil, viewport: nil)!
                let data = PNGEncoder.encodeRGBA(width: pixels.width, height: pixels.height, pixels: pixels.pixels)
                let url = URL(fileURLWithPath: "/tmp/rendertest2/\(name).png")
                try data.write(to: url)
                print("wrote \(url.path)")
            }
        } catch {
            print("debug dump failed: \(error)")
        }
    }

    /// A game sitting on the attract screen for a few seconds, so the demo
    /// traffic has spawned and the title pulse is mid-cycle.
    static func titleGame() -> Game {
        let game = Game(best: 12_345, seed: 1974)
        for _ in 0..<360 {
            game.update(controls: Controls.idle, dt: 1.0 / 60.0)
            _ = game.takeEvents()
        }
        return game
    }

    /// The same state the Rust `docs/gameplay.png` shows: a race in progress
    /// with traffic on screen.
    static func raceGame() -> Game {
        let game = Game(best: 12_345, seed: 1974)
        game.startRace()
        // Skip the countdown, then drive with the throttle on.
        for _ in 0..<200 {
            game.update(controls: Controls.idle, dt: 1.0 / 60.0)
            _ = game.takeEvents()
        }
        for frame in 0..<540 {
            let steer: Float = frame % 120 < 60 ? -0.15 : 0.15
            game.update(
                controls: Controls(steer: steer, throttle: 1.0, brake: 0.0), dt: 1.0 / 60.0)
            _ = game.takeEvents()
        }
        return game
    }

    /// Builds both draw lists exactly the way the app's frame pipeline does.
    static func renderFrame(
        renderer: MetalRenderer, game: Game, time: Float, muted: Bool
    ) throws -> (width: Int, height: Int, pixels: [UInt8])? {
        let crt = DrawList(aaScale: 1.0)
        crt.begin()
        CrtScene.draw(crt, game: game, time: time)

        let cabinet = DrawList(aaScale: 1.0)
        cabinet.begin()
        Cabinet.draw(cabinet, game: game, muted: muted)

        return try renderer.render(crt: crt, cabinet: cabinet, drawable: nil, viewport: nil)
    }
}
