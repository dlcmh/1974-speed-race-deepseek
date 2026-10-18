//! Keyboard and gamepad input.
//!
//! Keyboard steering is intentionally digital, like the original cabinet's
//! microswitches. A connected gamepad or wheel provides analog steering and
//! analog triggers for the accelerator and brake.

use gilrs::{Axis, Button, Gilrs};
use macroquad::prelude::*;

use crate::game::Controls;

pub struct InputState {
    pub controls: Controls,
    pub start: bool,
    pub pause: bool,
    pub quit: bool,
    pub mute: bool,
    pub fullscreen: bool,
    pub screenshot: bool,
}

pub struct Input {
    gilrs: Option<Gilrs>,
    prev_south: bool,
    prev_start: bool,
    prev_select: bool,
}

impl Input {
    pub fn new() -> Self {
        Self {
            gilrs: Gilrs::new().ok(),
            prev_south: false,
            prev_start: false,
            prev_select: false,
        }
    }

    pub fn poll(&mut self) -> InputState {
        let left = is_key_down(KeyCode::Left) || is_key_down(KeyCode::A);
        let right = is_key_down(KeyCode::Right) || is_key_down(KeyCode::D);
        let mut steer = (right as i32 - left as i32) as f32;
        let mut throttle: f32 =
            if is_key_down(KeyCode::Up) || is_key_down(KeyCode::W) || is_key_down(KeyCode::Space) {
                1.0
            } else {
                0.0
            };
        let mut brake: f32 = if is_key_down(KeyCode::Down) || is_key_down(KeyCode::S) {
            1.0
        } else {
            0.0
        };

        let mut start = is_key_pressed(KeyCode::Enter) || is_key_pressed(KeyCode::Space);
        let mut pause = is_key_pressed(KeyCode::P) || is_key_pressed(KeyCode::Escape);
        let mut quit = is_key_pressed(KeyCode::Q);
        let mute = is_key_pressed(KeyCode::M);
        let fullscreen = is_key_pressed(KeyCode::F);
        let screenshot = is_key_pressed(KeyCode::F12);

        if let Some(gilrs) = &mut self.gilrs {
            // Pump the event queue so hot-plugging and button state stay fresh.
            while gilrs.next_event().is_some() {}

            let pad_id = gilrs
                .gamepads()
                .find(|(_, gamepad)| gamepad.is_connected())
                .map(|(id, _)| id);

            if let Some(id) = pad_id {
                let pad = gilrs.gamepad(id);

                let stick = pad
                    .axis_data(Axis::LeftStickX)
                    .map(|axis| axis.value())
                    .unwrap_or(0.0);
                if stick.abs() > 0.12 {
                    steer = (steer + stick).clamp(-1.0, 1.0);
                }

                let dpad_left = pad.is_pressed(Button::DPadLeft);
                let dpad_right = pad.is_pressed(Button::DPadRight);
                steer += (dpad_right as i32 - dpad_left as i32) as f32;
                steer = steer.clamp(-1.0, 1.0);

                // Racing wheels usually expose pedals as Z axes; ordinary
                // controllers expose them as digital triggers.
                let right_trigger = pad
                    .axis_data(Axis::RightZ)
                    .map(|axis| axis.value().max(0.0))
                    .unwrap_or(0.0);
                let left_trigger = pad
                    .axis_data(Axis::LeftZ)
                    .map(|axis| axis.value().max(0.0))
                    .unwrap_or(0.0);
                let digital_gas = pad.is_pressed(Button::RightTrigger2)
                    || pad.is_pressed(Button::South)
                    || pad.is_pressed(Button::DPadUp);
                let digital_brake = pad.is_pressed(Button::LeftTrigger2)
                    || pad.is_pressed(Button::East)
                    || pad.is_pressed(Button::DPadDown);
                throttle = throttle
                    .max(right_trigger)
                    .max(if digital_gas { 1.0 } else { 0.0 });
                brake = brake
                    .max(left_trigger)
                    .max(if digital_brake { 1.0 } else { 0.0 });

                let south = pad.is_pressed(Button::South);
                let start_button = pad.is_pressed(Button::Start);
                let select = pad.is_pressed(Button::Select);
                if south && !self.prev_south {
                    start = true;
                }
                if start_button && !self.prev_start {
                    pause = true;
                }
                if select && !self.prev_select {
                    quit = true;
                }
                self.prev_south = south;
                self.prev_start = start_button;
                self.prev_select = select;
            } else {
                self.prev_south = false;
                self.prev_start = false;
                self.prev_select = false;
            }
        }

        InputState {
            controls: Controls {
                steer: steer.clamp(-1.0, 1.0),
                throttle: throttle.clamp(0.0, 1.0),
                brake: brake.clamp(0.0, 1.0),
            },
            start,
            pause,
            quit,
            mute,
            fullscreen,
            screenshot,
        }
    }
}
