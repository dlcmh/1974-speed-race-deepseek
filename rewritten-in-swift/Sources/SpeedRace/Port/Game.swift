import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/game.rs (canonical Rust game, repository root).
//
// Game rules, traffic, scoring and the crash/restart loop.
//
// The simulation is deliberately independent of Metal and AppKit: it takes a
// small input snapshot and a delta time, and reports what happened through
// events. That keeps it straightforward to test and lets the app own sound and
// pixels. This mirrors the Rust module one-for-one — see docs/PORTING.md for
// the symbol-level mapping and docs/PARITY.md for how equality is proven.

/// Snapshot of what the driver is asking the car to do this frame.
public struct Controls: Sendable, Equatable {
    /// -1 = left, +1 = right.
    public var steer: Float
    /// 0 = released, 1 = floored.
    public var throttle: Float
    /// 0 = released, 1 = floored.
    public var brake: Float

    public init(steer: Float = 0.0, throttle: Float = 0.0, brake: Float = 0.0) {
        self.steer = steer
        self.throttle = throttle
        self.brake = brake
    }

    public static let idle = Controls()
}

public enum Phase: Sendable, Equatable {
    case attract
    case countdown
    case racing
    case crashed
    case gameOver
}

/// What happened in the simulation this frame. The app drains these and maps
/// them to sound, exactly like Rust's `Event` + `take_events()`.
public enum RaceEvent: String, Sendable, Equatable {
    case countdownBeep = "CountdownBeep"
    case go = "Go"
    case overtake = "Overtake"
    case crash = "Crash"
    case extend = "Extend"
    case gameOver = "GameOver"
}

public struct TrafficCar: Sendable, Equatable {
    public var z: Float
    /// Normalised position across the road, -1 = left edge.
    public var lateral: Float
    public var speed: Float
    public var kind: UInt8
    public var variant: UInt8
    public var scored: Bool
    public var wobblePhase: Float

    public init(
        z: Float, lateral: Float, speed: Float, kind: UInt8, variant: UInt8,
        scored: Bool = false, wobblePhase: Float = 0.0
    ) {
        self.z = z
        self.lateral = lateral
        self.speed = speed
        self.kind = kind
        self.variant = variant
        self.scored = scored
        self.wobblePhase = wobblePhase
    }
}

public struct Spark: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var vx: Float
    public var vy: Float
    public var life: Float
    public var maxLife: Float
    public var size: Float
}

/// Text shown on the CRT for a short time (`Notice.text` in Rust).
///
/// Rust stores `&'static str`; Swift uses an enum so the renderer's
/// `match notice.text` stays exhaustive and the three special notices
/// (GO!, CRASH!, and the generic "banner" style) cannot be misspelled at the
/// call site. `rawValue` is what a parity trace records.
public enum NoticeText: String, Sendable, Equatable {
    case go = "GO!"
    case crash = "CRASH!"
    case trackRestarted = "TRACK RESTARTED"
    case timeExtended = "TIME EXTENDED +20"

    /// Rendered string. Rust uses the same UTF-8 bytes; the bitmap font has
    /// a glyph for every character used here.
    public var text: String { rawValue }
}

public struct Notice: Sendable, Equatable {
    public var text: NoticeText
    public var timer: Float
}

/// The complete game state. One instance per run; value semantics would copy
/// hundreds of bytes per frame for no benefit, so this is a reference type
/// and the app treats it as owned by the simulation thread.
public final class Game {
    public static let startTime: Float = 90.0
    public static let maxSpeed: Float = 240.0
    public static let playerZ: Float = 34.0

    /// Converts km/h into the abstract world units used by the road.
    static let kmhToUnits: Float = 4.0
    static let lanes: [Float] = [-0.66, -0.22, 0.22, 0.66]
    public static let playerLateralLimit: Float = 0.82
    static let collisionDz: Float = 38.0
    static let collisionDx: Float = 0.20

    public private(set) var phase: Phase = .attract
    public var paused = false
    public var timeLeft: Float = Game.startTime
    public var score: UInt32 = 0
    public var best: UInt32
    public var newBest = false
    public var bestDirty = false
    public var carsPassed: UInt32 = 0
    public var topSpeed: Float = 0.0
    public var speed: Float = 0.0
    public var lateral: Float = 0.0
    public var distance: Float = 0.0
    public var traffic: [TrafficCar] = []
    public var sparks: [Spark] = []
    public var controls = Controls.idle
    public var countdown: Float = 0.0
    public var crashTimer: Float = 0.0
    public var invulnerable: Float = 0.0
    public var flash: Float = 0.0
    public var shake: Float = 0.0
    public var notice: Notice?
    public var nextExtend: UInt32 = 1000
    public var extensionCount: UInt32 = 0
    public var raceClock: Float = 0.0
    public var lean: Float = 0.0
    public private(set) var events: [RaceEvent] = []
    public var demoClock: Float = 0.0
    private(set) var timeUpAnnounced = false

    public var rng: Rng
    var spawnTimer: Float = 1.0




    public init(best: UInt32, rng: Rng = .fromTime()) {
        self.best = best
        self.rng = rng
        seedTraffic()
    }

    /// Deterministic constructor used by tests and the parity harness.
    ///
    public convenience init(best: UInt32, seed: UInt64) {
        // `rng` alone would here resolve to this initialiser's *parameter*,
        // not the property, because the argument label shadows the property
        // name for implicit self. Writing `self.rng` keeps the compiler from
        // turning this into a self-assignment (a real bug the golden traces
        // caught: the game silently ran on the time-seeded RNG).
        self.init(best: best, rng: Rng(seed: seed))
    }

    // MARK: - Control

    public func startRace() {
        phase = .countdown
        paused = false
        timeLeft = Game.startTime
        score = 0
        newBest = false
        carsPassed = 0
        topSpeed = 0.0
        speed = 0.0
        lateral = 0.0
        distance = 0.0
        countdown = 3.0
        crashTimer = 0.0
        invulnerable = 0.0
        flash = 0.0
        shake = 0.0
        notice = nil
        nextExtend = 1000
        extensionCount = 0
        raceClock = 0.0
        lean = 0.0
        spawnTimer = 0.7
        timeUpAnnounced = false
        traffic.removeAll(keepingCapacity: true)
        sparks.removeAll(keepingCapacity: true)
        seedTraffic()
        events.append(.countdownBeep)
    }

    public func togglePause() {
        switch phase {
        case .countdown, .racing, .crashed:
            paused.toggle()
        case .attract, .gameOver:
            break
        }
    }

    public func update(controls: Controls, dt: Float) {
        self.controls = Controls(
            steer: rustClamp(controls.steer, -1.0, 1.0),
            throttle: rustClamp(controls.throttle, 0.0, 1.0),
            brake: rustClamp(controls.brake, 0.0, 1.0)
        )
        if paused {
            return
        }
        if phase == .gameOver {
            tickEffects(dt)
            return
        }

        switch phase {
        case .attract: updateAttract(dt)
        case .countdown: updateCountdown(dt)
        case .racing: updateRacing(dt)
        case .crashed: updateCrashed(dt)
        case .gameOver: break
        }
    }

    public func countdownNumber() -> UInt8? {
        guard phase == .countdown else { return nil }
        let number = UInt8(rustClamp(countdown.rounded(.up), 0.0, 3.0))
        return number > 0 ? number : nil
    }

    public func displayTime() -> UInt32 {
        UInt32(max(timeLeft, 0.0).rounded(.up))
    }

    /// Drains the event queue, exactly like `take_events()`.
    public func takeEvents() -> [RaceEvent] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }

    // MARK: - Private simulation (mirrors src/game.rs line by line)

    /// Rust `seed_traffic()`.
    ///
    /// Rust pushes the six starting cars with `traffic.push(TrafficCar { .. })`
    /// where the struct literal draws `variant` then `wobble_phase` from the
    /// RNG. `start_race()` clears the list first; `Game::new` does not (the
    /// list starts empty). The order of these draws is part of the
    /// deterministic contract, so it is spelled out explicitly here.
    func seedTraffic() {
        let starting: [(z: Float, lane: Int, speed: Float, kind: UInt8)] = [
            (230.0, 2, 44.0, 0),
            (430.0, 0, 50.0, 1),
            (650.0, 3, 43.0, 2),
            (890.0, 1, 55.0, 0),
            (1_150.0, 2, 49.0, 1),
            (1_390.0, 0, 46.0, 2),
        ]
        for car in starting {
            let variant = UInt8(rng.below(3))
            let wobblePhase = rng.range(0.0, .rustTau)
            traffic.append(
                TrafficCar(
                    z: car.z, lateral: Game.lanes[car.lane], speed: car.speed, kind: car.kind,
                    variant: variant, scored: false, wobblePhase: wobblePhase))
        }
    }

    func updateAttract(_ dt: Float) {
        demoClock += dt
        // Canonical call site resolves to `sinf` here (see RustMath.swift).
        speed = 96.0 + rustSinFloat(demoClock * 0.7) * 16.0
        lateral = rustSin(demoClock * 0.46) * 0.34
        lean = rustCos(demoClock * 0.46) * 0.5
        distance += speed * Game.kmhToUnits * dt
        spawnTimer -= dt
        if spawnTimer <= 0.0 {
            spawnTimer = rng.range(0.9, 1.7)
            trySpawn(maxCars: 9)
        }
        moveTraffic(dt, scoring: false)
        updateSparks(dt)
        tickEffects(dt)
    }

    func updateCountdown(_ dt: Float) {
        let before = Int32(countdown.rounded(.up))
        countdown -= dt
        let after = Int32(countdown.rounded(.up))
        if before != after && after > 0 {
            events.append(.countdownBeep)
        }
        if countdown <= 0.0 {
            countdown = 0.0
            phase = .racing
            notice = Notice(text: .go, timer: 0.9)
            events.append(.go)
        }
        tickEffects(dt)
    }

    func updateRacing(_ dt: Float) {
        raceClock += dt
        timeLeft -= dt
        if timeLeft <= 0.0 {
            finish()
            return
        }

        updateSpeed(dt)
        topSpeed = max(topSpeed, speed)
        updateSteering(dt)
        distance += speed * Game.kmhToUnits * dt

        moveTraffic(dt, scoring: true)
        if phase != .racing {
            return
        }

        spawnTimer -= dt
        if spawnTimer <= 0.0 {
            let difficulty = rustClamp(raceClock / 80.0, 0.0, 1.0)
            spawnTimer = 1.02 - difficulty * 0.44
            // Rust: `13 + (difficulty * 4.0) as usize` — truncating cast.
            let maxCars = 13 + Int(difficulty * 4.0)
            trySpawn(maxCars: maxCars)
        }

        updateExtensions()
        updateSparks(dt)
        tickEffects(dt)
    }

    func updateCrashed(_ dt: Float) {
        raceClock += dt
        timeLeft -= dt
        if timeLeft <= 0.0 {
            finish()
            return
        }
        crashTimer -= dt
        moveTraffic(dt, scoring: false)
        updateSparks(dt)
        tickEffects(dt)
        if crashTimer <= 0.0 {
            restartTrack()
        }
    }

    func updateSpeed(_ dt: Float) {
        let throttle = controls.throttle
        let brake = controls.brake
        let engineForce = 108.0 * throttle
        let drag =
            throttle > 0.01
            ? 16.0 + speed * 0.36
            : 27.0 + speed * 0.16
        let braking = 205.0 * brake
        speed += (engineForce - drag - braking) * dt
        speed = rustClamp(speed, 0.0, Game.maxSpeed)
    }

    func updateSteering(_ dt: Float) {
        let ratio = speed / Game.maxSpeed
        let responsiveness = 0.32 + ratio * 0.72
        lateral += controls.steer * responsiveness * dt

        // A banked curve pulls the car towards the outside. This is what makes
        // the sine-wave road something the player has to actively drive.
        let bend = Road.curvature(distance)
        lateral -= bend * 235.0 * ratio * ratio * dt

        if lateral > Game.playerLateralLimit {
            lateral = Game.playerLateralLimit
            speed = max(speed - 32.0 * dt, 0.0)
            shake = max(shake, 0.08)
        } else if lateral < -Game.playerLateralLimit {
            lateral = -Game.playerLateralLimit
            speed = max(speed - 32.0 * dt, 0.0)
            shake = max(shake, 0.08)
        }

        let targetLean = controls.steer * (0.35 + ratio * 0.65)
        lean += (targetLean - lean) * min(dt * 9.0, 1.0)
    }

    func moveTraffic(_ dt: Float, scoring: Bool) {
        let playerSpeed = speed
        var crash = false

        for index in traffic.indices {
            // Rust iterates `&mut self.traffic`, so every field write below is
            // visible in the array immediately. That matters on a crash frame:
            // cars visited before the crash keep their new `z`, cars after it
            // keep the old one. Writing through `traffic[index]` reproduces it;
            // collecting into a local copy would advance every car on the crash
            // frame (the golden traces caught exactly that).
            traffic[index].z -= (playerSpeed - traffic[index].speed) * Game.kmhToUnits * dt
            traffic[index].wobblePhase += dt * 2.2
            // Rust mutates the array element directly, so a `scored = true`
            // set just before a crash-triggered `break` is still recorded.
            // Writing each flag back immediately keeps that behaviour.
            if scoring {
                if !traffic[index].scored && traffic[index].z < Game.playerZ - 10.0
                    && traffic[index].z > Game.playerZ - 130.0
                {
                    traffic[index].scored = true
                    carsPassed += 1
                    // Rust: `80 + (self.speed * 0.42) as u32` — saturating float
                    // cast (negative/NaN -> 0), then wrapping-free u32 add.
                    let points = 80 &+ UInt32(rustSaturating: speed * 0.42)
                    score = score.addingReportingOverflow(points).partialValue
                    events.append(.overtake)
                }

                if invulnerable <= 0.0
                    && abs(traffic[index].z - Game.playerZ) <= Game.collisionDz
                    && abs(traffic[index].lateral - lateral) <= Game.collisionDx
                {
                    crash = true
                    break
                }
            }
        }

        traffic.removeAll { car in
            !(car.z > -140.0 && car.z < Road.viewDistance + 500.0)
        }

        if crash {
            self.crash()
        }
    }

    func trySpawn(maxCars: Int) {
        if traffic.count >= maxCars {
            return
        }
        let difficulty = rustClamp(raceClock / 80.0, 0.0, 1.0)
        let spawnZ = Road.viewDistance - rng.range(0.0, 120.0)
        let nearby = traffic.reduce(into: 0) { count, car in
            if abs(car.z - spawnZ) < 130.0 { count += 1 }
        }
        // Never stitch together a four-car wall that cannot be threaded.
        if nearby >= 3 {
            return
        }
        guard let lane = pickFreeLane(atZ: spawnZ) else {
            return
        }
        let speed = min(44.0 + rng.range(0.0, 55.0) + difficulty * 16.0, 132.0)
        // Draw order matches the Rust struct literal: lateral, speed uses no
        // RNG, then kind, variant, wobblePhase.
        let lateral = Game.lanes[lane] + rng.range(-0.025, 0.025)
        let kind = UInt8(rng.below(3))
        let variant = UInt8(rng.below(3))
        let wobble = rng.range(0.0, .rustTau)
        traffic.append(
            TrafficCar(
                z: spawnZ, lateral: lateral, speed: speed, kind: kind, variant: variant,
                scored: false, wobblePhase: wobble))
    }

    func pickFreeLane(atZ z: Float) -> Int? {
        var order = [0, 1, 2, 3]
        // Fisher-Yates from the back, exactly as Rust.
        if order.count > 1 {
            for i in stride(from: order.count - 1, through: 1, by: -1) {
                let j = rng.below(i + 1)
                order.swapAt(i, j)
            }
        }
        return order.first { lane in
            !traffic.contains { car in
                abs(car.z - z) < 190.0 && abs(car.lateral - Game.lanes[lane]) < 0.24
            }
        }
    }

    func crash() {
        guard phase == .racing else { return }
        phase = .crashed
        crashTimer = 1.45
        speed = 0.0
        flash = 1.0
        shake = 1.0
        notice = Notice(text: .crash, timer: 1.3)
        events.append(.crash)
        spawnSparks()
    }

    func restartTrack() {
        phase = .racing
        speed = 0.0
        lateral = 0.0
        distance = 0.0
        invulnerable = 1.8
        traffic.removeAll(keepingCapacity: true)
        seedTraffic()
        spawnTimer = 0.8
        notice = Notice(text: .trackRestarted, timer: 1.7)
    }

    func finish() {
        phase = .gameOver
        timeLeft = 0.0
        speed = 0.0
        paused = false
        notice = nil
        if !timeUpAnnounced {
            timeUpAnnounced = true
            events.append(.gameOver)
        }
        if score > best {
            best = score
            newBest = true
            bestDirty = true
        }
    }

    func updateExtensions() {
        while score >= nextExtend {
            timeLeft += 20.0
            extensionCount += 1
            let step = 1500 &+ extensionCount &* 500
            nextExtend = nextExtend.addingReportingOverflow(step).partialValue
            flash = max(flash, 0.55)
            notice = Notice(text: .timeExtended, timer: 1.7)
            events.append(.extend)
        }
    }

    func spawnSparks() {
        // Spark coordinates live in the 240 x 360 CRT space.
        for _ in 0..<28 {
            let life = rng.range(0.25, 0.9)
            let x = 120.0 + lateral * 76.0 + rng.range(-8.0, 8.0)
            let y = 316.0 + rng.range(-8.0, 8.0)
            let vx = rng.range(-95.0, 95.0)
            let vy = rng.range(-120.0, 15.0)
            let size = rng.range(1.0, 3.0)
            sparks.append(
                Spark(x: x, y: y, vx: vx, vy: vy, life: life, maxLife: life, size: size))
        }
    }

    func updateSparks(_ dt: Float) {
        for index in sparks.indices {
            sparks[index].x += sparks[index].vx * dt
            sparks[index].y += sparks[index].vy * dt
            sparks[index].vy += 155.0 * dt
            sparks[index].life -= dt
        }
        sparks.removeAll { spark in spark.life <= 0.0 }
    }

    func tickEffects(_ dt: Float) {
        if var notice = notice {
            notice.timer -= dt
            if notice.timer <= 0.0 {
                self.notice = nil
            } else {
                self.notice = notice
            }
        }
        flash = max(flash - dt * 2.4, 0.0)
        shake = max(shake - dt * 2.8, 0.0)
        invulnerable = max(invulnerable - dt, 0.0)
    }
}

// MARK: - Test hooks
//
// The Rust tests reach directly into `Game`'s fields (`game.phase =
// Phase::Racing`, `game.update_extensions()`). Swift keeps `phase` read-only
// from outside the type, so the port exposes the same capabilities through
// these explicitly named hooks. They are `public` only because the parity
// runner lives in a separate module; the app never calls them, and they are
// listed in docs/DIVERGENCES.md D-0003.

extension Game {
    public var rngDiag: Rng {
        get { rng }
        set { rng = newValue }
    }
    public func seedTrafficDiag() { seedTraffic() }
    public var trafficDiag: [TrafficCar] {
        get { traffic }
        set { traffic = newValue }
    }

    /// Equivalent to Rust's `game.phase = Phase::Racing;` in a test.
    public func forcePhase(_ newPhase: Phase) {
        phase = newPhase
    }

    /// Equivalent to Rust's `game.update_extensions();` in a test.
    public func updateExtensionsForTest() {
        updateExtensions()
    }
}


/// Stable names for fixtures and bug reports.
extension Phase {
    public var rawFixtureName: String {
        switch self {
        case .attract: return "Attract"
        case .countdown: return "Countdown"
        case .racing: return "Racing"
        case .crashed: return "Crashed"
        case .gameOver: return "GameOver"
        }
    }
}
