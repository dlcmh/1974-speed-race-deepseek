// swift-tools-version: 6.0
//
// Speed Race (1974) — Swift + Metal port of the canonical Rust game in the
// repository root (src/*.rs, pinned at commit d5f4420).
//
// Decisions and their rationale live in docs/DECISIONS.md. The Rust <-> Swift
// mapping is in docs/PORTING.md. Nothing here may silently diverge from the
// Rust reference; every intentional difference is listed in
// docs/DIVERGENCES.md.
//
// Deliberately zero third-party dependencies: the game uses only Apple
// frameworks (AppKit, Metal, AVFoundation, GameController). The Rust game's
// "no asset pipeline" rule is preserved by compiling every pixel and every
// sample in code.

import PackageDescription

let package = Package(
    name: "SpeedRace",
    platforms: [
        // macOS 14 keeps Swift 6 language mode, GameController's newer
        // controller APIs and AVAudioSourceNode comfortably available.
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpeedRace", targets: ["SpeedRace"]),
        .executable(name: "speed-race", targets: ["SpeedRaceCLI"]),
        .executable(name: "parity-check", targets: ["ParityCheck"]),
        .executable(name: "speed-race-render", targets: ["SpeedRaceRender"]),
        .executable(name: "speed-race-app", targets: ["SpeedRaceApp"])
    ],
    targets: [
        .target(
            // All game code lives in a library so both executables can link
            // it: the windowed app and the headless parity/test runner.
            name: "SpeedRace",
            path: "Sources/SpeedRace",
            resources: [
                // Shaders are compiled at launch (see docs/DECISIONS.md,
                // "P-0004"). Shipping the source as a resource keeps the
                // package buildable with Command Line Tools only. `.copy`
                // keeps the file verbatim: `.process` would invoke the Metal
                // compiler, which Command Line Tools does not ship.
                .copy("Render/Shaders.metal")
            ]
        ),
        .executableTarget(
            // The playable game: AppKit window + MTKView + keyboard.
            name: "SpeedRaceApp",
            dependencies: ["SpeedRace"],
            path: "Sources/SpeedRaceApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("GameController"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            // Headless renderer for visual verification (`--render`).
            name: "SpeedRaceRender",
            dependencies: ["SpeedRace"],
            path: "Sources/SpeedRaceRender"
        ),
        .executableTarget(
            // Temporary headless smoke runner (see main.swift in the target).
            name: "SpeedRaceCLI",
            dependencies: ["SpeedRace"],
            path: "Sources/SpeedRaceCLI"
        ),
        .executableTarget(
            // The Rust game's 14 unit tests are ported into this runner
            // rather than XCTest or Swift Testing: on this machine only
            // Command Line Tools are installed and neither test framework
            // ships with them (docs/DECISIONS.md P-0002).
            //
            // `swift run parity-check` prints a pass/fail summary, performs
            // the golden trace replay (Fixtures/parity) and is what
            // docs/PARITY.md names as the verification gate.
            name: "ParityCheck",
            dependencies: ["SpeedRace"],
            path: "Tests/ParityCheck"
        )
    ]
)
