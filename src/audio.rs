//! Real-time procedural arcade audio.
//!
//! The engine is a continuously running software oscillator rendered inside
//! the audio callback. It is not a looping WAV, so there is no loop seam and
//! no restart when the revs change. One-shot effects are synthesised in the
//! same callback. No audio assets or unsafe code are involved.

use std::f32::consts::TAU;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SampleFormat, SizedSample, StreamConfig};

#[derive(Clone, Copy)]
enum Cue {
    Countdown,
    Go,
    Crash,
    Extend,
    GameOver,
    Pass,
}

struct Shared {
    running: AtomicBool,
    muted: AtomicBool,
    speed: AtomicU32,
    throttle: AtomicU32,
}

impl Shared {
    fn new() -> Self {
        Self {
            running: AtomicBool::new(false),
            muted: AtomicBool::new(false),
            speed: AtomicU32::new(0.0f32.to_bits()),
            throttle: AtomicU32::new(0.0f32.to_bits()),
        }
    }

    fn speed(&self) -> f32 {
        f32::from_bits(self.speed.load(Ordering::Relaxed))
    }

    fn throttle(&self) -> f32 {
        f32::from_bits(self.throttle.load(Ordering::Relaxed))
    }
}

pub struct ArcadeAudio {
    shared: Arc<Shared>,
    cue_tx: Sender<Cue>,
    /// Dropping this sender tells the audio thread to release its stream.
    _stop_tx: Sender<()>,
    pub muted: bool,
}

impl ArcadeAudio {
    pub fn load() -> Self {
        let shared = Arc::new(Shared::new());
        let (cue_tx, cue_rx) = mpsc::channel();
        let (stop_tx, stop_rx) = mpsc::channel();

        let audio_shared = Arc::clone(&shared);
        std::thread::Builder::new()
            .name("speed-race-audio".to_owned())
            .spawn(move || {
                if let Err(error) = run_audio(audio_shared, cue_rx, stop_rx) {
                    eprintln!("Speed Race audio unavailable: {error}");
                }
            })
            .ok();

        Self {
            shared,
            cue_tx,
            _stop_tx: stop_tx,
            muted: false,
        }
    }

    pub fn toggle_mute(&mut self) {
        self.muted = !self.muted;
        self.shared.muted.store(self.muted, Ordering::Relaxed);
        if self.muted {
            self.shared.running.store(false, Ordering::Relaxed);
        }
    }

    /// Feed the continuous engine synth. Pitch and level follow speed and
    /// throttle; there is no sample switching to click or gap.
    pub fn sync_engine(&mut self, active: bool, speed: f32, throttle: f32) {
        let running = active && !self.muted;
        self.shared.running.store(running, Ordering::Relaxed);
        self.shared
            .speed
            .store(speed.clamp(0.0, 240.0).to_bits(), Ordering::Relaxed);
        self.shared
            .throttle
            .store(throttle.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    pub fn stop_engine(&mut self) {
        self.shared.running.store(false, Ordering::Relaxed);
    }

    pub fn countdown(&self) {
        self.send(Cue::Countdown);
    }

    pub fn go(&self) {
        self.send(Cue::Go);
    }

    pub fn crash(&self) {
        self.send(Cue::Crash);
    }

    pub fn extend(&self) {
        self.send(Cue::Extend);
    }

    pub fn game_over(&self) {
        self.send(Cue::GameOver);
    }

    pub fn pass(&self) {
        self.send(Cue::Pass);
    }

    fn send(&self, cue: Cue) {
        if !self.muted {
            let _ = self.cue_tx.send(cue);
        }
    }
}

fn run_audio(
    shared: Arc<Shared>,
    cues: Receiver<Cue>,
    stop_rx: Receiver<()>,
) -> Result<(), String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or_else(|| "no default output device".to_owned())?;
    let supported = device
        .default_output_config()
        .map_err(|error| format!("no default output config: {error}"))?;
    let sample_format = supported.sample_format();
    let config = supported.config();

    let stream = match sample_format {
        SampleFormat::F32 => build_stream::<f32>(&device, &config, shared, cues),
        SampleFormat::F64 => build_stream::<f64>(&device, &config, shared, cues),
        SampleFormat::I16 => build_stream::<i16>(&device, &config, shared, cues),
        SampleFormat::I32 => build_stream::<i32>(&device, &config, shared, cues),
        SampleFormat::U16 => build_stream::<u16>(&device, &config, shared, cues),
        SampleFormat::U32 => build_stream::<u32>(&device, &config, shared, cues),
        other => Err(format!("unsupported sample format: {other}")),
    }
    .map_err(|error| format!("could not open output stream: {error}"))?;

    stream
        .play()
        .map_err(|error| format!("could not start output stream: {error}"))?;

    // Keep the stream alive until the app drops ArcadeAudio.
    let _ = stop_rx.recv();
    Ok(())
}

fn build_stream<T>(
    device: &cpal::Device,
    config: &StreamConfig,
    shared: Arc<Shared>,
    cues: Receiver<Cue>,
) -> Result<cpal::Stream, String>
where
    T: SizedSample + FromSample<f32>,
{
    let channels = config.channels.max(1) as usize;
    let sample_rate = config.sample_rate as f32;
    let mut mixer = Mixer::new(sample_rate);

    device
        .build_output_stream(
            *config,
            move |data: &mut [T], _| mixer.render(data, channels, &shared, &cues),
            |error| eprintln!("Speed Race audio stream error: {error}"),
            None,
        )
        .map_err(|error| error.to_string())
}

struct Mixer {
    engine: Engine,
    voices: [Option<Voice>; 8],
    sample_rate: f32,
}

impl Mixer {
    fn new(sample_rate: f32) -> Self {
        Self {
            engine: Engine::new(sample_rate),
            voices: [const { None }; 8],
            sample_rate,
        }
    }

    fn render<T>(&mut self, data: &mut [T], channels: usize, shared: &Shared, cues: &Receiver<Cue>)
    where
        T: SizedSample + FromSample<f32>,
    {
        while let Ok(cue) = cues.try_recv() {
            self.add_voice(cue);
        }

        let muted = shared.muted.load(Ordering::Relaxed);
        if muted {
            for voice in &mut self.voices {
                *voice = None;
            }
        }

        for frame in data.chunks_mut(channels) {
            // Keep advancing the engine while muted so its amplitude envelope
            // reaches zero and unmuting cannot produce a sudden jump.
            let engine_sample = self.engine.next_sample(shared);
            let mut sample = if muted { 0.0 } else { engine_sample };

            if !muted {
                for slot in &mut self.voices {
                    if let Some(voice) = slot {
                        if voice.finished() {
                            *slot = None;
                        } else {
                            sample += voice.next_sample();
                        }
                    }
                }
            }

            let sample = sample.clamp(-1.0, 1.0);
            let value = T::from_sample(sample);
            for output in frame.iter_mut() {
                *output = value;
            }
        }
    }

    fn add_voice(&mut self, cue: Cue) {
        let voice = Voice::new(cue, self.sample_rate);
        if let Some(slot) = self.voices.iter_mut().find(|slot| slot.is_none()) {
            *slot = Some(voice);
        } else if let Some(slot) = self.voices.first_mut() {
            *slot = Some(voice);
        }
    }
}

struct Engine {
    phase: f32,
    frequency: f32,
    amplitude: f32,
    noise: f32,
    rng: u32,
    sample_rate: f32,
    time: f32,
}

impl Engine {
    fn new(sample_rate: f32) -> Self {
        Self {
            phase: 0.0,
            frequency: 54.0,
            amplitude: 0.0,
            noise: 0.0,
            rng: 0x1974_0055,
            sample_rate,
            time: 0.0,
        }
    }

    fn next_sample(&mut self, shared: &Shared) -> f32 {
        let speed_ratio = (shared.speed() / 240.0).clamp(0.0, 1.0);
        let throttle = shared.throttle().clamp(0.0, 1.0);
        let running = shared.running.load(Ordering::Relaxed);

        let target_frequency = 54.0 + 72.0 * speed_ratio + 8.0 * throttle;
        let target_amplitude = if running {
            0.20 + 0.25 * throttle + 0.10 * speed_ratio
        } else {
            0.0
        };

        // Smooth both pitch and level so pause/resume and rev changes glide.
        let freq_smoothing = 1.0 - (-1.0 / (0.045 * self.sample_rate)).exp();
        let amp_time = if target_amplitude > self.amplitude {
            0.018
        } else {
            0.10
        };
        let amp_smoothing = 1.0 - (-1.0 / (amp_time * self.sample_rate)).exp();

        self.frequency += (target_frequency - self.frequency) * freq_smoothing;
        self.amplitude += (target_amplitude - self.amplitude) * amp_smoothing;
        self.time += 1.0 / self.sample_rate;

        self.phase = (self.phase + self.frequency / self.sample_rate).fract();
        let phase = self.phase * TAU;
        let wobble = 1.0 + 0.012 * (self.time * TAU * 3.0).sin();

        let mut sample = (phase * wobble).sin() * 0.52
            + (phase * 2.0).sin() * 0.23
            + (phase * 3.0).sin() * 0.12
            + (phase * 4.0).sin() * 0.06
            + (phase * 5.0).sin() * 0.05
            + (phase * 7.0).sin() * 0.035;

        self.rng = self.rng.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        let white = (self.rng >> 8) as f32 / 8_388_608.0 - 1.0;
        self.noise += (white - self.noise) * 0.08;
        sample += self.noise * 0.10;

        (sample * 1.8).tanh() * self.amplitude
    }
}

#[derive(Clone, Copy)]
enum VoiceKind {
    Countdown,
    Go,
    Crash,
    Extend,
    GameOver,
    Pass,
}

struct Voice {
    kind: VoiceKind,
    age: f32,
    duration: f32,
    sample_rate: f32,
    noise: f32,
    rng: u32,
}

impl Voice {
    fn new(cue: Cue, sample_rate: f32) -> Self {
        let (kind, duration, rng) = match cue {
            Cue::Countdown => (VoiceKind::Countdown, 0.11, 0x1000_0001),
            Cue::Go => (VoiceKind::Go, 0.26, 0x1000_0002),
            Cue::Crash => (VoiceKind::Crash, 0.85, 0xDEAD_BEEF),
            Cue::Extend => (VoiceKind::Extend, 0.78, 0x1000_0003),
            Cue::GameOver => (VoiceKind::GameOver, 1.5, 0x1000_0004),
            Cue::Pass => (VoiceKind::Pass, 0.035, 0x1000_0005),
        };
        Self {
            kind,
            age: 0.0,
            duration,
            sample_rate,
            noise: 0.0,
            rng,
        }
    }

    fn finished(&self) -> bool {
        self.age >= self.duration
    }

    fn next_sample(&mut self) -> f32 {
        let age = self.age;
        let t = age / self.duration;
        let value = match self.kind {
            VoiceKind::Countdown => tone(age, 660.0, self.duration, 0.86),
            VoiceKind::Go => tone(age, 990.0, self.duration, 0.86),
            VoiceKind::Pass => tone(age, 1_320.0, self.duration, 0.46),
            VoiceKind::Crash => {
                self.rng = self.rng.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                let white = (self.rng >> 9) as f32 / 4_194_304.0 - 1.0;
                self.noise += (white - self.noise) * 0.31;
                let fade = (1.0 - t).powf(1.4);
                let thud = (age * 52.0 * TAU).sin() * (1.0 - age / 0.4).max(0.0);
                ((self.noise * 0.8 + thud * 0.55) * fade * 0.82).clamp(-1.0, 1.0)
            }
            VoiceKind::Extend => {
                let mut sample = 0.0;
                for (start, frequency, length) in [
                    (0.0, 660.0, 0.18),
                    (0.16, 880.0, 0.18),
                    (0.32, 1_320.0, 0.34),
                ] {
                    if age >= start && age < start + length {
                        sample += tone(age - start, frequency, length, 0.8);
                    }
                }
                sample.clamp(-1.0, 1.0)
            }
            VoiceKind::GameOver => {
                let mut sample = 0.0;
                for (start, frequency, length) in [
                    (0.0, 392.0, 0.22),
                    (0.22, 330.0, 0.22),
                    (0.44, 262.0, 0.25),
                    (0.74, 196.0, 0.55),
                ] {
                    if age >= start && age < start + length {
                        sample += tone(age - start, frequency, length, 0.8);
                    }
                }
                sample.clamp(-1.0, 1.0)
            }
        };

        self.age += 1.0 / self.sample_rate;
        value
    }
}

fn tone(age: f32, frequency: f32, duration: f32, gain: f32) -> f32 {
    if age < 0.0 || age >= duration {
        return 0.0;
    }
    let t = age / duration;
    let attack = (age * 90.0).clamp(0.0, 1.0);
    let release = (1.0 - t).powf(1.3);
    let phase = age * frequency * TAU;
    let wave = phase.sin() + (phase * 2.0).sin() * 0.18;
    (wave * 0.5).tanh() * gain * attack * release
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_output_is_finite_and_bounded() {
        let shared = Shared::new();
        shared.running.store(true, Ordering::Relaxed);
        shared.speed.store(240.0f32.to_bits(), Ordering::Relaxed);
        shared.throttle.store(1.0f32.to_bits(), Ordering::Relaxed);
        let mut engine = Engine::new(48_000.0);

        let mut previous = 0.0;
        let mut max_step = 0.0f32;
        for _ in 0..48_000 {
            let sample = engine.next_sample(&shared);
            assert!(sample.is_finite());
            assert!(sample.abs() <= 0.6);
            max_step = max_step.max((sample - previous).abs());
            previous = sample;
        }
        assert!(max_step < 0.2, "engine jumped by {max_step}");
    }

    #[test]
    fn engine_pitch_glides_without_restarts() {
        let shared = Shared::new();
        shared.running.store(true, Ordering::Relaxed);
        shared.speed.store(0.0f32.to_bits(), Ordering::Relaxed);
        let mut engine = Engine::new(48_000.0);
        for _ in 0..2_000 {
            engine.next_sample(&shared);
        }
        let low = engine.frequency;

        shared.speed.store(240.0f32.to_bits(), Ordering::Relaxed);
        let mut previous = engine.frequency;
        let mut max_step = 0.0f32;
        for _ in 0..10_000 {
            engine.next_sample(&shared);
            max_step = max_step.max((engine.frequency - previous).abs());
            previous = engine.frequency;
        }
        assert!(engine.frequency > low + 50.0);
        assert!(max_step < 1.0, "pitch stepped by {max_step} Hz");
    }

    #[test]
    fn every_sound_ends_inside_its_buffer() {
        for cue in [
            Cue::Countdown,
            Cue::Go,
            Cue::Crash,
            Cue::Extend,
            Cue::GameOver,
            Cue::Pass,
        ] {
            let mut voice = Voice::new(cue, 48_000.0);
            let mut last = 0.0;
            let mut rendered = 0;
            while !voice.finished() && rendered < 100_000 {
                last = voice.next_sample();
                rendered += 1;
                assert!(last.is_finite());
                assert!(last.abs() <= 1.0);
            }
            assert!(voice.finished());
            assert!(last.abs() < 0.2, "voice ended abruptly at {last}");
        }
    }
}
