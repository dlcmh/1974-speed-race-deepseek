import AVFoundation
import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// PORT OF: src/audio.rs.
//
// Same design as the canonical game (ADR-0012 there): one continuously running
// software oscillator, rendered inside the audio callback, plus one-shot voices
// synthesised in the same callback. No audio assets, no looping buffer, so
// there is no loop seam and no restart click when the revs change.
//
// The Rust version shares state with the audio thread through atomics. Here the
// same fields live in a small lock-free struct read by the render block:
// 32-bit float and word loads/stores are single-copy atomic on arm64, and every
// field is a snapshot whose worst case is one frame of staleness — the same
// guarantee the atomics provided. Nothing blocks or allocates in the callback.

/// Parameters the game thread publishes for the audio thread.
final class AudioParameters {
    private let storage: UnsafeMutablePointer<UInt32>

    init() {
        storage = .allocate(capacity: 4)
        storage.initialize(repeating: 0, count: 4)
        storage[0] = 0  // running
        storage[1] = 0  // muted
        storage[2] = Float(0).bitPattern  // speed
        storage[3] = Float(0).bitPattern  // throttle
    }

    deinit { storage.deallocate() }

    var running: Bool {
        get { storage[0] != 0 }
        set { storage[0] = newValue ? 1 : 0 }
    }
    var muted: Bool {
        get { storage[1] != 0 }
        set { storage[1] = newValue ? 1 : 0 }
    }
    var speed: Float {
        get { Float(bitPattern: storage[2]) }
        set { storage[2] = newValue.bitPattern }
    }
    var throttle: Float {
        get { Float(bitPattern: storage[3]) }
        set { storage[3] = newValue.bitPattern }
    }
}

/// Cues, matching `Cue` in audio.rs.
enum AudioCue {
    case countdown
    case go
    case crash
    case extend
    case gameOver
    case pass
}

/// Real-time synthesiser. Mirrors `Engine`, `Voice` and `tone` from audio.rs.
final class Synthesizer {
    private let sampleRate: Float
    // Engine state
    private var phase: Float = 0
    private var frequency: Float = 54
    private var amplitude: Float = 0
    private var noise: Float = 0
    private var rng: UInt32 = 0x1974_0055
    private var time: Float = 0
    // Voices
    private var voices: [Voice?] = Array(repeating: nil, count: 8)
    private var pending: [AudioCue] = []

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    /// Queues a one-shot. Called from the game thread; appends are cheap and the
    /// callback drains them at the top of the buffer, like the Rust channel.
    func enqueue(_ cue: AudioCue) {
        if pending.count < 16 { pending.append(cue) }
    }

    func render(into buffer: UnsafeMutablePointer<Float>, frames: Int, parameters: AudioParameters) {
        while let cue = pending.first {
            pending.removeFirst()
            addVoice(cue)
        }
        let muted = parameters.muted
        if muted {
            for index in voices.indices { voices[index] = nil }
        }
        let speed = parameters.speed
        let throttle = parameters.throttle
        let running = parameters.running

        for frame in 0..<frames {
            var sample = muted ? 0 : engineSample(speed: speed, throttle: throttle, running: running)
            if !muted {
                for index in voices.indices {
                    guard var voice = voices[index] else { continue }
                    if voice.finished {
                        voices[index] = nil
                    } else {
                        sample += voice.nextSample(sampleRate: sampleRate)
                        voices[index] = voice
                    }
                }
            }
            buffer[frame] = max(-1, min(1, sample))
        }
    }

    private func engineSample(speed: Float, throttle: Float, running: Bool) -> Float {
        let speedRatio = min(max(speed / 240, 0), 1)
        let targetFrequency = 54 + 72 * speedRatio + 8 * throttle
        let targetAmplitude: Float = running ? 0.20 + 0.25 * throttle + 0.10 * speedRatio : 0

        let freqSmoothing = 1 - exp(-1 / (0.045 * sampleRate))
        let ampTime: Float = targetAmplitude > amplitude ? 0.018 : 0.10
        let ampSmoothing = 1 - exp(-1 / (ampTime * sampleRate))

        frequency += (targetFrequency - frequency) * freqSmoothing
        amplitude += (targetAmplitude - amplitude) * ampSmoothing
        time += 1 / sampleRate

        phase += frequency / sampleRate
        if phase >= 1 { phase -= 1 }
        let angle = phase * Float.rustTau
        let wobble = 1 + 0.012 * rustSin(time * Float.rustTau * 3)

        var sample = rustSin(angle * wobble) * 0.52
            + rustSin(angle * 2) * 0.23
            + rustSin(angle * 3) * 0.12
            + rustSin(angle * 4) * 0.06
            + rustSin(angle * 5) * 0.05
            + rustSin(angle * 7) * 0.035

        rng = rng &* 1_664_525 &+ 1_013_904_223
        let white = Float(rng >> 8) / 8_388_608 - 1
        noise += (white - noise) * 0.08
        sample += noise * 0.10

        return tanh(sample * 1.8) * amplitude
    }

    private func addVoice(_ cue: AudioCue) {
        let voice = Voice(cue: cue)
        if let slot = voices.firstIndex(where: { $0 == nil }) {
            voices[slot] = voice
        } else {
            voices[0] = voice
        }
    }
}

/// One-shot voice, mirroring `Voice` in audio.rs.
private struct Voice {
    enum Kind {
        case countdown, go, crash, extend, gameOver, pass
    }

    let kind: Kind
    var age: Float = 0
    let duration: Float
    var noise: Float = 0
    var rng: UInt32

    init(cue: AudioCue) {
        switch cue {
        case .countdown: kind = .countdown; duration = 0.11; rng = 0x1000_0001
        case .go: kind = .go; duration = 0.26; rng = 0x1000_0002
        case .crash: kind = .crash; duration = 0.85; rng = 0xDEAD_BEEF
        case .extend: kind = .extend; duration = 0.78; rng = 0x1000_0003
        case .gameOver: kind = .gameOver; duration = 1.5; rng = 0x1000_0004
        case .pass: kind = .pass; duration = 0.035; rng = 0x1000_0005
        }
    }

    var finished: Bool { age >= duration }

    mutating func nextSample(sampleRate: Float) -> Float {
        let t = age / duration
        var value: Float = 0
        switch kind {
        case .countdown: value = tone(age, 660, duration, 0.86)
        case .go: value = tone(age, 990, duration, 0.86)
        case .pass: value = tone(age, 1_320, duration, 0.46)
        case .crash:
            rng = rng &* 1_103_515_245 &+ 12_345
            let white = Float(rng >> 9) / 4_194_304 - 1
            noise += (white - noise) * 0.31
            let fade = pow(1 - t, 1.4)
            let thud = rustSin(age * 52 * Float.rustTau) * max(1 - age / 0.4, 0)
            value = max(-1, min(1, (noise * 0.8 + thud * 0.55) * fade * 0.82))
        case .extend:
            var sample: Float = 0
            for (start, frequency, length) in [(Float(0), Float(660), Float(0.18)),
                                               (0.16, 880, 0.18), (0.32, 1_320, 0.34)] {
                if age >= start && age < start + length {
                    sample += tone(age - start, frequency, length, 0.8)
                }
            }
            value = max(-1, min(1, sample))
        case .gameOver:
            var sample: Float = 0
            for (start, frequency, length) in [(Float(0), Float(392), Float(0.22)),
                                               (0.22, 330, 0.22), (0.44, 262, 0.25),
                                               (0.74, 196, 0.55)] {
                if age >= start && age < start + length {
                    sample += tone(age - start, frequency, length, 0.8)
                }
            }
            value = max(-1, min(1, sample))
        }
        age += 1 / sampleRate
        return value
    }

    /// `tone()` from audio.rs.
    private func tone(_ age: Float, _ frequency: Float, _ duration: Float, _ gain: Float) -> Float {
        if age < 0 || age >= duration { return 0 }
        let t = age / duration
        let attack = min(max(age * 90, 0), 1)
        let release = pow(1 - t, 1.3)
        let phase = age * frequency * Float.rustTau
        let wave = rustSin(phase) + rustSin(phase * 2) * 0.18
        return tanh(wave * 0.5) * gain * attack * release
    }
}

/// Hosts the synthesiser on an `AVAudioEngine` source node.
public final class ArcadeAudio {
    private let engine = AVAudioEngine()
    private let parameters = AudioParameters()
    private let synthesizer: Synthesizer
    private var source: AVAudioSourceNode?
    public private(set) var muted = false
    /// True when the audio device could not be opened; the game runs silently,
    /// exactly like the Rust fallback.
    public private(set) var unavailable = false

    public init() {
        let rate: Float = 48_000
        synthesizer = Synthesizer(sampleRate: rate)
        start(rate: rate)
    }

    private func start(rate: Float) {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2)
        guard let format else {
            unavailable = true
            return
        }
        let synth = synthesizer
        let params = parameters
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = list.first, let data = first.mData else { return noErr }
            let frames = Int(frameCount)
            let pointer = data.assumingMemoryBound(to: Float.self)
            // Render once, then copy to every channel (the Rust mixer writes the
            // same sample to all channels of a frame).
            synth.render(into: pointer, frames: frames, parameters: params)
            for index in 1..<list.count {
                if let channel = list[index].mData {
                    channel.copyMemory(from: data, byteCount: frames * MemoryLayout<Float>.size)
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            unavailable = true
            NSLog("Speed Race audio unavailable: %@", String(describing: error))
        }
    }

    /// Mute toggle, matching `toggle_mute` (muting also stops the engine sound).
    public func toggleMute() {
        muted.toggle()
        parameters.muted = muted
        if muted { parameters.running = false }
    }

    /// Feeds the continuous engine synth.
    public func syncEngine(active: Bool, speed: Float, throttle: Float) {
        parameters.running = active && !muted
        parameters.speed = min(max(speed, 0), 240)
        parameters.throttle = min(max(throttle, 0), 1)
    }

    public func stopEngine() {
        parameters.running = false
    }

    public func countdown() { play(.countdown) }
    public func go() { play(.go) }
    public func crash() { play(.crash) }
    public func extend() { play(.extend) }
    public func gameOver() { play(.gameOver) }
    public func pass() { play(.pass) }

    private func play(_ cue: AudioCue) {
        if !muted { synthesizer.enqueue(cue) }
    }
}
