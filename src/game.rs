//! Game rules, traffic, scoring and the crash/restart loop.
//!
//! The simulation is deliberately independent of macroquad: it takes a small
//! input snapshot and a delta time, and reports what happened through events.
//! That keeps it straightforward to test and lets `main` own sound and pixels.

use crate::rng::Rng;
use crate::road::{self, VIEW_DISTANCE};

pub const START_TIME: f32 = 90.0;
pub const MAX_SPEED: f32 = 240.0;
pub const PLAYER_Z: f32 = 34.0;

/// Converts km/h into the abstract world units used by the road.
const KMH_TO_UNITS: f32 = 4.0;
const LANES: [f32; 4] = [-0.66, -0.22, 0.22, 0.66];
const PLAYER_LATERAL_LIMIT: f32 = 0.82;
const COLLISION_DZ: f32 = 38.0;
const COLLISION_DX: f32 = 0.20;

#[derive(Clone, Copy, Debug, Default)]
pub struct Controls {
    /// -1 = left, +1 = right.
    pub steer: f32,
    /// 0 = released, 1 = floored.
    pub throttle: f32,
    /// 0 = released, 1 = floored.
    pub brake: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Attract,
    Countdown,
    Racing,
    Crashed,
    GameOver,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    CountdownBeep,
    Go,
    Overtake,
    Crash,
    Extend,
    GameOver,
}

#[derive(Clone, Copy, Debug)]
pub struct TrafficCar {
    pub z: f32,
    /// Normalised position across the road, -1 = left edge.
    pub lateral: f32,
    pub speed: f32,
    pub kind: u8,
    pub variant: u8,
    pub scored: bool,
    pub wobble_phase: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct Spark {
    pub x: f32,
    pub y: f32,
    pub vx: f32,
    pub vy: f32,
    pub life: f32,
    pub max_life: f32,
    pub size: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct Notice {
    pub text: &'static str,
    pub timer: f32,
}

pub struct Game {
    pub phase: Phase,
    pub paused: bool,
    pub time_left: f32,
    pub score: u32,
    pub best: u32,
    pub new_best: bool,
    pub best_dirty: bool,
    pub cars_passed: u32,
    pub top_speed: f32,
    pub speed: f32,
    pub lateral: f32,
    pub distance: f32,
    pub traffic: Vec<TrafficCar>,
    pub sparks: Vec<Spark>,
    pub controls: Controls,
    pub countdown: f32,
    pub crash_timer: f32,
    pub invulnerable: f32,
    pub flash: f32,
    pub shake: f32,
    pub notice: Option<Notice>,
    pub next_extend: u32,
    pub extension_count: u32,
    pub race_clock: f32,
    pub lean: f32,
    pub events: Vec<Event>,

    rng: Rng,
    spawn_timer: f32,
    pub demo_clock: f32,
    time_up_announced: bool,
}

impl Game {
    pub fn new(best: u32) -> Self {
        let mut game = Self {
            phase: Phase::Attract,
            paused: false,
            time_left: START_TIME,
            score: 0,
            best,
            new_best: false,
            best_dirty: false,
            cars_passed: 0,
            top_speed: 0.0,
            speed: 0.0,
            lateral: 0.0,
            distance: 0.0,
            traffic: Vec::new(),
            sparks: Vec::new(),
            controls: Controls::default(),
            countdown: 0.0,
            crash_timer: 0.0,
            invulnerable: 0.0,
            flash: 0.0,
            shake: 0.0,
            notice: None,
            next_extend: 1000,
            extension_count: 0,
            race_clock: 0.0,
            lean: 0.0,
            events: Vec::new(),
            rng: Rng::from_time(),
            spawn_timer: 1.0,
            demo_clock: 0.0,
            time_up_announced: false,
        };
        game.seed_traffic();
        game
    }

    #[cfg(test)]
    pub fn with_seed(best: u32, seed: u64) -> Self {
        let mut game = Self::new(best);
        game.rng = Rng::new(seed);
        game
    }

    pub fn start_race(&mut self) {
        self.phase = Phase::Countdown;
        self.paused = false;
        self.time_left = START_TIME;
        self.score = 0;
        self.new_best = false;
        self.cars_passed = 0;
        self.top_speed = 0.0;
        self.speed = 0.0;
        self.lateral = 0.0;
        self.distance = 0.0;
        self.countdown = 3.0;
        self.crash_timer = 0.0;
        self.invulnerable = 0.0;
        self.flash = 0.0;
        self.shake = 0.0;
        self.notice = None;
        self.next_extend = 1000;
        self.extension_count = 0;
        self.race_clock = 0.0;
        self.lean = 0.0;
        self.spawn_timer = 0.7;
        self.time_up_announced = false;
        self.traffic.clear();
        self.sparks.clear();
        self.seed_traffic();
        self.events.push(Event::CountdownBeep);
    }

    pub fn toggle_pause(&mut self) {
        if matches!(
            self.phase,
            Phase::Countdown | Phase::Racing | Phase::Crashed
        ) {
            self.paused = !self.paused;
        }
    }

    pub fn update(&mut self, controls: Controls, dt: f32) {
        self.controls = Controls {
            steer: controls.steer.clamp(-1.0, 1.0),
            throttle: controls.throttle.clamp(0.0, 1.0),
            brake: controls.brake.clamp(0.0, 1.0),
        };
        if self.paused {
            return;
        }
        if self.phase == Phase::GameOver {
            self.tick_effects(dt);
            return;
        }

        match self.phase {
            Phase::Attract => self.update_attract(dt),
            Phase::Countdown => self.update_countdown(dt),
            Phase::Racing => self.update_racing(dt),
            Phase::Crashed => self.update_crashed(dt),
            Phase::GameOver => {}
        }
    }

    pub fn countdown_number(&self) -> Option<u8> {
        if self.phase != Phase::Countdown {
            return None;
        }
        let number = self.countdown.ceil().clamp(0.0, 3.0) as u8;
        (number > 0).then_some(number)
    }

    pub fn display_time(&self) -> u32 {
        self.time_left.max(0.0).ceil() as u32
    }

    pub fn take_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }

    fn seed_traffic(&mut self) {
        let starting = [
            (230.0, 2, 44.0, 0),
            (430.0, 0, 50.0, 1),
            (650.0, 3, 43.0, 2),
            (890.0, 1, 55.0, 0),
            (1_150.0, 2, 49.0, 1),
            (1_390.0, 0, 46.0, 2),
        ];
        for (z, lane, speed, kind) in starting {
            self.traffic.push(TrafficCar {
                z,
                lateral: LANES[lane],
                speed,
                kind,
                variant: self.rng.below(3) as u8,
                scored: false,
                wobble_phase: self.rng.range(0.0, std::f32::consts::TAU),
            });
        }
    }

    fn update_attract(&mut self, dt: f32) {
        self.demo_clock += dt;
        self.speed = 96.0 + (self.demo_clock * 0.7).sin() * 16.0;
        self.lateral = (self.demo_clock * 0.46).sin() * 0.34;
        self.lean = (self.demo_clock * 0.46).cos() * 0.5;
        self.distance += self.speed * KMH_TO_UNITS * dt;
        self.spawn_timer -= dt;
        if self.spawn_timer <= 0.0 {
            self.spawn_timer = self.rng.range(0.9, 1.7);
            self.try_spawn(9);
        }
        self.move_traffic(dt, false);
        self.update_sparks(dt);
        self.tick_effects(dt);
    }

    fn update_countdown(&mut self, dt: f32) {
        let before = self.countdown.ceil() as i32;
        self.countdown -= dt;
        let after = self.countdown.ceil() as i32;
        if before != after && after > 0 {
            self.events.push(Event::CountdownBeep);
        }
        if self.countdown <= 0.0 {
            self.countdown = 0.0;
            self.phase = Phase::Racing;
            self.notice = Some(Notice {
                text: "GO!",
                timer: 0.9,
            });
            self.events.push(Event::Go);
        }
        self.tick_effects(dt);
    }

    fn update_racing(&mut self, dt: f32) {
        self.race_clock += dt;
        self.time_left -= dt;
        if self.time_left <= 0.0 {
            self.finish();
            return;
        }

        self.update_speed(dt);
        self.top_speed = self.top_speed.max(self.speed);
        self.update_steering(dt);
        self.distance += self.speed * KMH_TO_UNITS * dt;

        self.move_traffic(dt, true);
        if self.phase != Phase::Racing {
            return;
        }

        self.spawn_timer -= dt;
        if self.spawn_timer <= 0.0 {
            let difficulty = (self.race_clock / 80.0).clamp(0.0, 1.0);
            self.spawn_timer = 1.02 - difficulty * 0.44;
            let max_cars = 13 + (difficulty * 4.0) as usize;
            self.try_spawn(max_cars);
        }

        self.update_extensions();
        self.update_sparks(dt);
        self.tick_effects(dt);
    }

    fn update_crashed(&mut self, dt: f32) {
        self.race_clock += dt;
        self.time_left -= dt;
        if self.time_left <= 0.0 {
            self.finish();
            return;
        }
        self.crash_timer -= dt;
        self.move_traffic(dt, false);
        self.update_sparks(dt);
        self.tick_effects(dt);
        if self.crash_timer <= 0.0 {
            self.restart_track();
        }
    }

    fn update_speed(&mut self, dt: f32) {
        let throttle = self.controls.throttle;
        let brake = self.controls.brake;
        let engine_force = 108.0 * throttle;
        let drag = if throttle > 0.01 {
            16.0 + self.speed * 0.36
        } else {
            27.0 + self.speed * 0.16
        };
        let braking = 205.0 * brake;
        self.speed += (engine_force - drag - braking) * dt;
        self.speed = self.speed.clamp(0.0, MAX_SPEED);
    }

    fn update_steering(&mut self, dt: f32) {
        let ratio = self.speed / MAX_SPEED;
        let responsiveness = 0.32 + ratio * 0.72;
        self.lateral += self.controls.steer * responsiveness * dt;

        // A banked curve pulls the car towards the outside. This is what makes
        // the sine-wave road something the player has to actively drive.
        let bend = road::curvature(self.distance);
        self.lateral -= bend * 235.0 * ratio * ratio * dt;

        if self.lateral > PLAYER_LATERAL_LIMIT {
            self.lateral = PLAYER_LATERAL_LIMIT;
            self.speed = (self.speed - 32.0 * dt).max(0.0);
            self.shake = self.shake.max(0.08);
        } else if self.lateral < -PLAYER_LATERAL_LIMIT {
            self.lateral = -PLAYER_LATERAL_LIMIT;
            self.speed = (self.speed - 32.0 * dt).max(0.0);
            self.shake = self.shake.max(0.08);
        }

        let target_lean = self.controls.steer * (0.35 + ratio * 0.65);
        self.lean += (target_lean - self.lean) * (dt * 9.0).min(1.0);
    }

    fn move_traffic(&mut self, dt: f32, scoring: bool) {
        let player_speed = self.speed;
        let mut crash = false;

        for car in &mut self.traffic {
            car.z -= (player_speed - car.speed) * KMH_TO_UNITS * dt;
            car.wobble_phase += dt * 2.2;

            if scoring {
                if !car.scored && car.z < PLAYER_Z - 10.0 && car.z > PLAYER_Z - 130.0 {
                    car.scored = true;
                    self.cars_passed += 1;
                    let points = 80 + (self.speed * 0.42) as u32;
                    self.score = self.score.saturating_add(points);
                    self.events.push(Event::Overtake);
                }

                if self.invulnerable <= 0.0
                    && (car.z - PLAYER_Z).abs() <= COLLISION_DZ
                    && (car.lateral - self.lateral).abs() <= COLLISION_DX
                {
                    crash = true;
                    break;
                }
            }
        }

        self.traffic
            .retain(|car| car.z > -140.0 && car.z < VIEW_DISTANCE + 500.0);

        if crash {
            self.crash();
        }
    }

    fn try_spawn(&mut self, max_cars: usize) {
        if self.traffic.len() >= max_cars {
            return;
        }
        let difficulty = (self.race_clock / 80.0).clamp(0.0, 1.0);
        let spawn_z = VIEW_DISTANCE - self.rng.range(0.0, 120.0);
        let nearby = self
            .traffic
            .iter()
            .filter(|car| (car.z - spawn_z).abs() < 130.0)
            .count();
        // Never stitch together a four-car wall that cannot be threaded.
        if nearby >= 3 {
            return;
        }
        let lane = self.pick_free_lane(spawn_z);
        let Some(lane) = lane else {
            return;
        };
        let speed = (44.0 + self.rng.range(0.0, 55.0) + difficulty * 16.0).min(132.0);
        self.traffic.push(TrafficCar {
            z: spawn_z,
            lateral: LANES[lane] + self.rng.range(-0.025, 0.025),
            speed,
            kind: self.rng.below(3) as u8,
            variant: self.rng.below(3) as u8,
            scored: false,
            wobble_phase: self.rng.range(0.0, std::f32::consts::TAU),
        });
    }

    fn pick_free_lane(&mut self, z: f32) -> Option<usize> {
        let mut order = [0usize, 1, 2, 3];
        for i in (1..order.len()).rev() {
            let j = self.rng.below(i + 1);
            order.swap(i, j);
        }
        order.into_iter().find(|&lane| {
            !self
                .traffic
                .iter()
                .any(|car| (car.z - z).abs() < 190.0 && (car.lateral - LANES[lane]).abs() < 0.24)
        })
    }

    fn crash(&mut self) {
        if self.phase != Phase::Racing {
            return;
        }
        self.phase = Phase::Crashed;
        self.crash_timer = 1.45;
        self.speed = 0.0;
        self.flash = 1.0;
        self.shake = 1.0;
        self.notice = Some(Notice {
            text: "CRASH!",
            timer: 1.3,
        });
        self.events.push(Event::Crash);
        self.spawn_sparks();
    }

    fn restart_track(&mut self) {
        self.phase = Phase::Racing;
        self.speed = 0.0;
        self.lateral = 0.0;
        self.distance = 0.0;
        self.invulnerable = 1.8;
        self.traffic.clear();
        self.seed_traffic();
        self.spawn_timer = 0.8;
        self.notice = Some(Notice {
            text: "TRACK RESTARTED",
            timer: 1.7,
        });
    }

    fn finish(&mut self) {
        self.phase = Phase::GameOver;
        self.time_left = 0.0;
        self.speed = 0.0;
        self.paused = false;
        self.notice = None;
        if !self.time_up_announced {
            self.time_up_announced = true;
            self.events.push(Event::GameOver);
        }
        if self.score > self.best {
            self.best = self.score;
            self.new_best = true;
            self.best_dirty = true;
        }
    }

    fn update_extensions(&mut self) {
        while self.score >= self.next_extend {
            self.time_left += 20.0;
            self.extension_count += 1;
            self.next_extend = self
                .next_extend
                .saturating_add(1500 + self.extension_count * 500);
            self.flash = self.flash.max(0.55);
            self.notice = Some(Notice {
                text: "TIME EXTENDED +20",
                timer: 1.7,
            });
            self.events.push(Event::Extend);
        }
    }

    fn spawn_sparks(&mut self) {
        for _ in 0..28 {
            let life = self.rng.range(0.25, 0.9);
            self.sparks.push(Spark {
                x: 120.0 + self.lateral * 76.0 + self.rng.range(-8.0, 8.0),
                y: 316.0 + self.rng.range(-8.0, 8.0),
                vx: self.rng.range(-95.0, 95.0),
                vy: self.rng.range(-120.0, 15.0),
                life,
                max_life: life,
                size: self.rng.range(1.0, 3.0),
            });
        }
    }

    fn update_sparks(&mut self, dt: f32) {
        for spark in &mut self.sparks {
            spark.x += spark.vx * dt;
            spark.y += spark.vy * dt;
            spark.vy += 155.0 * dt;
            spark.life -= dt;
        }
        self.sparks.retain(|spark| spark.life > 0.0);
    }

    fn tick_effects(&mut self, dt: f32) {
        if let Some(notice) = &mut self.notice {
            notice.timer -= dt;
            if notice.timer <= 0.0 {
                self.notice = None;
            }
        }
        self.flash = (self.flash - dt * 2.4).max(0.0);
        self.shake = (self.shake - dt * 2.8).max(0.0);
        self.invulnerable = (self.invulnerable - dt).max(0.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn advance(game: &mut Game, seconds: f32) {
        let steps = (seconds / 0.016).ceil() as usize;
        for _ in 0..steps {
            game.update(
                Controls {
                    throttle: 1.0,
                    ..Default::default()
                },
                0.016,
            );
        }
    }

    #[test]
    fn countdown_hands_over_to_the_timer() {
        let mut game = Game::with_seed(0, 1974);
        game.start_race();
        assert_eq!(game.phase, Phase::Countdown);
        advance(&mut game, 3.1);
        assert_eq!(game.phase, Phase::Racing);
        assert!(game.time_left < START_TIME);
        assert!(game.time_left > START_TIME - 1.0);
    }

    #[test]
    fn timer_expiry_ends_the_run_and_records_a_best() {
        let mut game = Game::with_seed(0, 7);
        game.start_race();
        game.phase = Phase::Racing;
        game.score = 4321;
        game.time_left = 0.01;
        game.update(Controls::default(), 0.02);
        assert_eq!(game.phase, Phase::GameOver);
        assert_eq!(game.best, 4321);
        assert!(game.new_best);
        assert!(game.best_dirty);
        assert!(game.take_events().contains(&Event::GameOver));
    }

    #[test]
    fn overtaking_awards_points_based_on_speed() {
        let mut game = Game::with_seed(0, 12);
        game.start_race();
        game.phase = Phase::Racing;
        game.speed = 180.0;
        game.traffic.clear();
        game.traffic.push(TrafficCar {
            z: PLAYER_Z - 20.0,
            lateral: 0.66,
            speed: 40.0,
            kind: 0,
            variant: 0,
            scored: false,
            wobble_phase: 0.0,
        });
        game.update(Controls::default(), 0.016);
        assert!(game.score >= 150);
        assert!(game.take_events().contains(&Event::Overtake));
    }

    #[test]
    fn a_car_in_your_lane_causes_a_crash_and_then_a_restart() {
        let mut game = Game::with_seed(0, 99);
        game.start_race();
        game.phase = Phase::Racing;
        game.speed = 120.0;
        game.traffic.clear();
        game.traffic.push(TrafficCar {
            z: PLAYER_Z,
            lateral: 0.0,
            speed: 110.0,
            kind: 1,
            variant: 1,
            scored: false,
            wobble_phase: 0.0,
        });
        game.update(Controls::default(), 0.016);
        assert_eq!(game.phase, Phase::Crashed);
        assert!(game.take_events().contains(&Event::Crash));
        let timer_before = game.time_left;
        advance(&mut game, 1.6);
        assert_eq!(game.phase, Phase::Racing);
        assert!(game.time_left <= timer_before);
        assert!(game.traffic.len() >= 4);
    }

    #[test]
    fn reaching_the_extend_threshold_adds_time() {
        let mut game = Game::with_seed(0, 5);
        game.start_race();
        game.phase = Phase::Racing;
        game.time_left = 30.0;
        game.score = 1000;
        game.next_extend = 1000;
        game.update_extensions();
        assert!(game.time_left >= 49.9);
        assert!(game.next_extend > 1000);
        assert!(game.take_events().contains(&Event::Extend));
    }

    #[test]
    fn steering_can_reach_both_edges_but_never_leaves_the_road() {
        let mut game = Game::with_seed(0, 3);
        game.start_race();
        game.phase = Phase::Racing;
        game.time_left = 60.0;
        game.speed = 160.0;
        for _ in 0..400 {
            game.update(
                Controls {
                    steer: -1.0,
                    throttle: 1.0,
                    ..Default::default()
                },
                0.016,
            );
        }
        assert!(game.lateral >= -PLAYER_LATERAL_LIMIT - 0.001);
        for _ in 0..400 {
            game.update(
                Controls {
                    steer: 1.0,
                    throttle: 1.0,
                    ..Default::default()
                },
                0.016,
            );
        }
        assert!(game.lateral <= PLAYER_LATERAL_LIMIT + 0.001);
    }
}
