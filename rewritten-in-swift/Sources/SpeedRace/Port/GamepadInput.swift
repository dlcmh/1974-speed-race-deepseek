import Foundation
import GameController

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: the gilrs half of src/input.rs.
//
// The canonical game reads the first connected gamepad or racing wheel and
// merges it with the keyboard:
//   * left stick / wheel axis steers (dead zone 0.12), d-pad adds digital input
//   * right trigger or A / d-pad-up accelerates
//   * left trigger or B / d-pad-down brakes
//   * A starts, Start pauses, Select/Back quits; button edges are tracked
//     locally so a held button does not retrigger
//
// Apple's GameController framework is the equivalent of gilrs. Triggers are
// analog (0...1) on modern controllers and wheels, which maps directly onto the
// Rust code's `right_trigger`/`left_trigger` axes.

/// Snapshot of the pad for one frame.
struct GamepadState {
    var steer: Float = 0
    var throttle: Float = 0
    var brake: Float = 0
    var startPressed = false
    var pausePressed = false
    var quitPressed = false
    var connected = false
}

/// Reads the first connected controller, mirroring `gilrs` usage in the Rust
/// game (only the first pad is used; hot-plugging is picked up automatically).
final class GamepadInput {
    private var previousSouth = false
    private var previousStart = false
    private var previousSelect = false

    init() {
        // Touching `current` on the main thread starts the framework's
        // connection monitoring, which is what makes hot-plugging work.
        _ = GCController.current
    }

    var isConnected: Bool { GCController.current != nil }

    func poll() -> GamepadState {
        var state = GamepadState()
        guard let controller = GCController.current else {
            previousSouth = false
            previousStart = false
            previousSelect = false
            return state
        }
        state.connected = true

        // Racing wheels and gamepads both expose an extended profile.
        let pad = controller.extendedGamepad
        let dpad = controller.microGamepad

        var steer: Float = 0
        if let pad {
            let stick = pad.leftThumbstick.xAxis.value
            if abs(stick) > 0.12 { steer += stick }
            if pad.dpad.right.isPressed { steer += 1 }
            if pad.dpad.left.isPressed { steer -= 1 }
            state.throttle = max(pad.rightTrigger.value, pad.buttonA.isPressed ? 1 : 0)
            state.brake = max(pad.leftTrigger.value, pad.buttonB.isPressed ? 1 : 0)
            if pad.dpad.up.isPressed { state.throttle = max(state.throttle, 1) }
            if pad.dpad.down.isPressed { state.brake = max(state.brake, 1) }

            let south = pad.buttonA.isPressed
            let start = pad.buttonMenu.isPressed
            if south && !previousSouth { state.startPressed = true }
            if start && !previousStart { state.pausePressed = true }
            previousSouth = south
            previousStart = start
            previousSelect = false
        } else if let dpad {
            // Micro (Siri Remote style) profile: no triggers, so use buttons.
            if dpad.dpad.right.isPressed { steer += 1 }
            if dpad.dpad.left.isPressed { steer -= 1 }
            state.throttle = dpad.buttonA.isPressed ? 1 : 0
            state.brake = dpad.buttonX.isPressed ? 1 : 0
            let south = dpad.buttonA.isPressed
            if south && !previousSouth { state.startPressed = true }
            previousSouth = south
        }

        state.steer = max(-1, min(1, steer))
        return state
    }
}
