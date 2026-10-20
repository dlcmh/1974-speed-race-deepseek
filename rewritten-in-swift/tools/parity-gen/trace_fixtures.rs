// Golden-trace driver for the Swift + Metal port.
//
// COMPILED AGAINST VERBATIM COPIES of the canonical Rust modules
// (src/game.rs, src/rng.rs, src/road.rs) by generate.sh. It plays a set of
// seeded input scripts through the real Rust `Game` and writes one JSON Lines
// fixture per scenario into Fixtures/parity/.
//
// Every frame line records the input applied and the state that came out, with
// f32 values encoded as raw IEEE-754 bit patterns so the Swift side can compare
// exactly. Format v2 — see docs/INVESTIGATION-parity.md:
//
//   {"header":true,"format":"speed-race-parity","version":2,
//    "scenario":"full-throttle","seed":1974,"best":0,
//    "rust_commit":"d5f4420","frames":6000,"dt":1026205126,
//    "plays_race":true,"seed_mode":"live","game_seed":0,
//    "restart_on_start":true,"start_restarts":1,"time_up_announced":false,
//    "first_traffic":"0197..."}
//
//   {"t":0,"in":[steer,throttle,brake bits...],"phase":"Racing","paused":false,
//    "speed":..,"lateral":..,"distance":..,"time_left":..,"score":..,
//    "cars_passed":..,"best":..,"new_best":bool,"best_dirty":bool,
//    "flash":..,"shake":..,"invulnerable":..,"lean":..,"countdown":..,
//    "crash_timer":..,"race_clock":..,"next_extend":..,"extension_count":..,
//    "top_speed":..,"notice":{"text":"GO!","timer":..}|null,
//    "traffic":[[z,lateral,speed,kind,variant,scored,wobble_phase],...],
//    "spark_count":..,"events":["CountdownBeep","Go"]}
//
//   {"rng_check":true,"seed":1974,"raw":[u64...],"unit":[bits...],...}
//
// `seed_mode`
//   "live"  — the scenario is meant to run as a normal app launch would:
//             `Game::new(best)` with a time-seeded RNG. Seed-derived fields
//             other than state (`best`, `rocks`) are unknowable, so `best` is 0
//             and the Swift side compares them only against this header.
//   "seeded" — the scenario builds `Game::with_seed(best, seed)`, which is
//             exactly what the Rust unit tests do. Fully reproducible, traffic
//             included.
//
// `restart_on_start`
//   Whether the scenario calls `start_race()` after constructing the game.
//   `start_race()` clears and reseeds traffic *from the same RNG stream*, so a
//   scenario that restarts effectively skips ahead twelve draws. The baseline
//   driver in trace_baseline.rs covers the complementary case (no restart).
//
// Keep this writer and ../../Tests/ParityCheck/ParityTrace.swift in lockstep.

use std::fmt::Write as _;

use crate::game::{Controls, Event, Game, Notice, Phase};
use crate::rng::Rng;

pub const FORMAT_VERSION: u32 = 2;

/// How a scenario obtains its `Game`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SeedMode {
    Live,
    Seeded(u64),
}

impl SeedMode {
    fn label(self) -> &'static str {
        match self {
            SeedMode::Live => "live",
            SeedMode::Seeded(_) => "seeded",
        }
    }

}

pub struct Scenario {
    pub name: &'static str,
    pub mode: SeedMode,
    pub best: u32,
    pub frames: usize,
    pub dt: f32,
    pub restart_on_start: bool,
    /// Input for frame `t` (0-based, after setup and the optional restart).
    pub inputs: fn(usize, f32) -> Controls,
}

fn scenarios(dt: f32) -> Vec<Scenario> {
    vec![
        // A normal race at full throttle with keyboard-style binary steering.
        Scenario {
            name: "seeded-race",
            mode: SeedMode::Seeded(1974),
            best: 0,
            frames: 6_000,
            dt,
            restart_on_start: true,
            inputs: |frame, _| Controls {
                steer: if (frame / 90) % 2 == 0 { -1.0 } else { 1.0 },
                throttle: 1.0,
                brake: 0.0,
            },
        },
        // Same, but with an existing high score (exercises best/new_best).
        Scenario {
            name: "seeded-race-with-best",
            mode: SeedMode::Seeded(0x5EED_1974),
            best: 12_345,
            frames: 6_000,
            dt,
            restart_on_start: true,
            inputs: |frame, dt| {
                let t = frame as f32 * dt;
                Controls {
                    steer: (t * 0.9).sin(),
                    throttle: ((t * 0.7).cos() * 0.5 + 0.55).clamp(0.0, 1.0),
                    brake: if (frame / 240) % 5 == 0 { 0.6 } else { 0.0 },
                }
            },
        },
        // Seeded, no restart: the attract loop (demo road, demo traffic).
        Scenario {
            name: "seeded-attract",
            mode: SeedMode::Seeded(42),
            best: 999,
            frames: 2_400,
            dt,
            restart_on_start: false,
            inputs: |_, _| Controls::default(),
        },
        // The canonical app launch: `Game::new` with a clock seed, then the
        // player presses Enter. Only `start_race()`-time state is comparable.
        Scenario {
            name: "live-launch",
            mode: SeedMode::Live,
            best: 0,
            frames: 3_600,
            dt,
            restart_on_start: true,
            inputs: |frame, _| Controls {
                steer: 0.0,
                throttle: if frame < 180 { 0.0 } else { 1.0 },
                brake: 0.0,
            },
        },
    ]
}

/// Post-construction setup, applied after an optional `start_race`.

pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    let out_dir = args.get(1).cloned().unwrap_or_else(|| ".".to_owned());
    let commit = args.get(2).cloned().unwrap_or_else(|| "unknown".to_owned());
    std::fs::create_dir_all(&out_dir).expect("create output directory");

    let dt: f32 = 1.0 / 60.0;
    for scenario in scenarios(dt) {
        std::fs::write(
            format!("{out_dir}/{}.jsonl", scenario.name),
            run_scenario(&scenario, &commit),
        )
        .expect("write fixture");
        println!("wrote {}/{}.jsonl", out_dir, scenario.name);
    }
}

fn run_scenario(scenario: &Scenario, commit: &str) -> String {
    let mut text = String::new();
    let (mut game, game_seed) = match scenario.mode {
        SeedMode::Live => (Game::new(scenario.best), 0),
        // `Game::with_seed(best, seed)` (canonical, `#[cfg(test)]`) calls
        // `Game::new(best)` first — which seeds traffic from the *clock* RNG —
        // and only then swaps in `Rng::new(seed)`. Its constructed traffic is
        // therefore not reproducible from `seed`. The scenarios instead build
        // the same observable state explicitly, with the clock dependency
        // removed. docs/INVESTIGATION-parity.md explains why this is a faithful model.
        SeedMode::Seeded(seed) => {
            let mut game = Game::new(scenario.best);
            game.traffic.clear();
            game.rng = Rng::new(seed);
            game.seed_traffic();
            (game, seed.max(1))
        }
    };
    let mut start_restarts = 0usize;
    if scenario.restart_on_start {
        game.start_race();
        start_restarts = 1;
    }

    let _ = writeln!(
        text,
        "{{\"header\":true,\"format\":\"speed-race-parity\",\"version\":{},\
         \"scenario\":\"{}\",\"seed\":{},\"best\":{},\"rust_commit\":\"{}\",\
         \"frames\":{},\"dt\":{},\"plays_race\":{},\"seed_mode\":\"{}\",\
         \"game_seed\":{},\"start_restarts\":{}}}",
        FORMAT_VERSION,
        scenario.name,
        match scenario.mode {
            SeedMode::Live => 0,
            SeedMode::Seeded(seed) => seed,
        },
        scenario.best,
        commit,
        scenario.frames,
        bits(scenario.dt),
        start_restarts > 0,
        scenario.mode.label(),
        game_seed,
        start_restarts,
    );

    for frame in 0..scenario.frames {
        let controls = (scenario.inputs)(frame, scenario.dt);
        game.update(controls, scenario.dt);
        write_frame(&mut text, frame, controls, &game);
        let _ = game.take_events();
    }

    write_rng_check(
        &mut text,
        match scenario.mode {
            SeedMode::Live => 1974,
            SeedMode::Seeded(seed) => seed,
        },
        256,
    );
    text
}

fn write_frame(text: &mut String, frame: usize, controls: Controls, game: &Game) {
    let mut line = String::with_capacity(1024);
    let _ = write!(
        line,
        "{{\"t\":{},\"in\":[{},{},{}],\"phase\":\"{}\",\"paused\":{},",
        frame,
        bits(controls.steer),
        bits(controls.throttle),
        bits(controls.brake),
        phase_name(game.phase),
        game.paused,
    );
    let _ = write!(
        line,
        "\"speed\":{},\"lateral\":{},\"distance\":{},\"time_left\":{},",
        bits(game.speed),
        bits(game.lateral),
        bits(game.distance),
        bits(game.time_left),
    );
    let _ = write!(
        line,
        "\"score\":{},\"cars_passed\":{},\"best\":{},\"new_best\":{},\"best_dirty\":{},",
        game.score, game.cars_passed, game.best, game.new_best, game.best_dirty,
    );
    let _ = write!(
        line,
        "\"flash\":{},\"shake\":{},\"invulnerable\":{},\"lean\":{},",
        bits(game.flash),
        bits(game.shake),
        bits(game.invulnerable),
        bits(game.lean),
    );
    let _ = write!(
        line,
        "\"countdown\":{},\"crash_timer\":{},\"race_clock\":{},\"next_extend\":{},\
         \"extension_count\":{},\"top_speed\":{},",
        bits(game.countdown),
        bits(game.crash_timer),
        bits(game.race_clock),
        game.next_extend,
        game.extension_count,
        bits(game.top_speed),
    );
    let _ = write!(line, "\"notice\":{}", notice_json(game.notice.as_ref()));

    line.push_str(",\"traffic\":[");
    for (index, car) in game.traffic.iter().enumerate() {
        if index > 0 {
            line.push(',');
        }
        let _ = write!(
            line,
            "[{},{},{},{},{},{},{}]",
            bits(car.z),
            bits(car.lateral),
            bits(car.speed),
            car.kind,
            car.variant,
            car.scored,
            bits(car.wobble_phase),
        );
    }
    line.push(']');
    let _ = write!(line, ",\"spark_count\":{}", game.sparks.len());

    line.push_str(",\"events\":[");
    for (index, event) in game.events.iter().enumerate() {
        if index > 0 {
            line.push(',');
        }
        let _ = write!(line, "\"{}\"", event_name(*event));
    }
    line.push_str("]}\n");
    text.push_str(&line);
}

fn write_rng_check(text: &mut String, seed: u64, count: usize) {
    let seeded = Rng::new(seed);
    let mut raw = seeded.clone();
    let mut unit = seeded.clone();
    let mut below = seeded.clone();
    let mut range = seeded.clone();
    let raw_values: Vec<String> = (0..count).map(|_| raw.next_u64().to_string()).collect();
    let unit_values: Vec<String> = (0..count).map(|_| bits(unit.unit()).to_string()).collect();
    let below_values: Vec<String> = (0..count)
        .map(|i| below.below(1 + i % 7).to_string())
        .collect();
    let range_values: Vec<String> = (0..count)
        .map(|_| bits(range.range(-3.0, 7.0)).to_string())
        .collect();
    let _ = writeln!(
        text,
        "{{\"rng_check\":true,\"seed\":{},\"raw\":[{}],\"unit\":[{}],\"below\":[{}],\"range\":[{}]}}",
        seed,
        raw_values.join(","),
        unit_values.join(","),
        below_values.join(","),
        range_values.join(","),
    );
}

fn notice_json(notice: Option<&Notice>) -> String {
    match notice {
        None => "null".to_owned(),
        Some(notice) => format!(
            "{{\"text\":\"{}\",\"timer\":{}}}",
            escape(notice.text),
            bits(notice.timer)
        ),
    }
}

fn phase_name(phase: Phase) -> &'static str {
    match phase {
        Phase::Attract => "Attract",
        Phase::Countdown => "Countdown",
        Phase::Racing => "Racing",
        Phase::Crashed => "Crashed",
        Phase::GameOver => "GameOver",
    }
}

fn event_name(event: Event) -> &'static str {
    match event {
        Event::CountdownBeep => "CountdownBeep",
        Event::Go => "Go",
        Event::Overtake => "Overtake",
        Event::Crash => "Crash",
        Event::Extend => "Extend",
        Event::GameOver => "GameOver",
    }
}

fn escape(text: &str) -> String {
    text.replace('\\', "\\\\").replace('"', "\\\"")
}

fn bits(value: f32) -> u32 {
    value.to_bits()
}
