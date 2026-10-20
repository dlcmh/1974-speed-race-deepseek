import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/input.rs (keyboard half).
//
// The canonical game reads keyboard state as it polls, and a connected
// gamepad/racing wheel adds analog steering and triggers. This type holds the
// same state with the same mappings so the app can poll it once per frame.
//
// The OS cursor is never hidden: the canonical AGENTS.md forbids it, and the
// port has no mouse controls anyway.

/// One frame of input, matching `InputState` in `src/input.rs`.
public struct InputState: Sendable {
    public var controls = Controls.idle
    public var start = false
    public var pause = false
    public var quit = false
    public var mute = false
    public var fullscreen = false
    public var screenshot = false
}

/// Keyboard state, matching the Rust key bindings exactly:
/// `A/D/←/→` steer, `W/↑/Space` throttle, `S/↓` brake,
/// `Enter/Space` start, `P/Esc` pause, `M` mute, `F` fullscreen,
/// `F12` screenshot, `Q` quit.
public final class Input {
    private var held: Set<UInt16> = []
    private var pressedThisFrame: Set<UInt16> = []
    private let gamepad = GamepadInput()

    // macOS virtual key codes (Carbon HIToolbox), stable across layouts.
    enum Key {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let a: UInt16 = 0
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let w: UInt16 = 13
        static let q: UInt16 = 12
        static let m: UInt16 = 46
        static let p: UInt16 = 35
        static let f: UInt16 = 3
        static let space: UInt16 = 49
        static let enter: UInt16 = 36
        static let escape: UInt16 = 53
        static let f12: UInt16 = 111
    }

    public init() {}

    public func keyDown(_ code: UInt16) {
        // Auto-repeat is ignored: a key already held is not a new press.
        if !held.contains(code) {
            pressedThisFrame.insert(code)
        }
        held.insert(code)
    }

    public func keyUp(_ code: UInt16) {
        held.remove(code)
    }

    public func clear() {
        held.removeAll()
        pressedThisFrame.removeAll()
    }

    /// Polls one frame. Consumes the edge-triggered keys.
    public func poll() -> InputState {
        let left = held.contains(Key.left) || held.contains(Key.a)
        let right = held.contains(Key.right) || held.contains(Key.d)
        let steer = Float((right ? 1 : 0) - (left ? 1 : 0))
        let throttle: Float =
            (held.contains(Key.up) || held.contains(Key.w) || held.contains(Key.space))
            ? 1.0 : 0.0
        let brake: Float = (held.contains(Key.down) || held.contains(Key.s)) ? 1.0 : 0.0

        // Merge the first connected pad or wheel, exactly like gilrs in Rust:
        // analog steering is added to the digital keyboard value, pedals take
        // the maximum, and button edges trigger start/pause/quit.
        let pad = gamepad.poll()
        var mergedSteer = steer
        var mergedThrottle = throttle
        var mergedBrake = brake
        var padStart = false
        var padPause = false
        var padQuit = false
        if pad.connected {
            mergedSteer = max(-1, min(1, mergedSteer + pad.steer))
            mergedThrottle = max(mergedThrottle, pad.throttle)
            mergedBrake = max(mergedBrake, pad.brake)
            padStart = pad.startPressed
            padPause = pad.pausePressed
            padQuit = pad.quitPressed
        }

        var state = InputState()
        state.controls = Controls(
            steer: mergedSteer, throttle: mergedThrottle, brake: mergedBrake)
        state.start = pressed(Key.enter) || pressed(Key.space) || padStart
        state.pause = pressed(Key.p) || pressed(Key.escape) || padPause
        state.quit = pressed(Key.q) || padQuit
        state.mute = pressed(Key.m)
        state.fullscreen = pressed(Key.f)
        state.screenshot = pressed(Key.f12)
        pressedThisFrame.removeAll(keepingCapacity: true)
        return state
    }

    private func pressed(_ code: UInt16) -> Bool {
        pressedThisFrame.contains(code)
    }
}
