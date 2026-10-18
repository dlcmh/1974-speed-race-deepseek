//! Tiny procedural arcade sound bank.
//!
//! Every sound is synthesised into a mono 16-bit WAV in memory and handed to
//! macroquad's mixer. There are no audio assets to ship, and no unsafe code.

use macroquad::audio::{
    PlaySoundParams, Sound, load_sound_from_bytes, play_sound, set_sound_volume, stop_sound,
};

const SAMPLE_RATE: u32 = 22_050;
const ENGINE_BUCKETS: usize = 6;

pub struct ArcadeAudio {
    engines: Vec<Sound>,
    countdown: Option<Sound>,
    go: Option<Sound>,
    crash: Option<Sound>,
    extend: Option<Sound>,
    game_over: Option<Sound>,
    pass: Option<Sound>,
    engine_bucket: Option<usize>,
    pub muted: bool,
}

impl ArcadeAudio {
    pub async fn load() -> Self {
        let mut engines = Vec::new();
        for bucket in 0..ENGINE_BUCKETS {
            if let Ok(sound) = load_sound_from_bytes(&engine_loop(bucket)).await {
                engines.push(sound);
            }
        }

        Self {
            engines,
            countdown: load_sound_from_bytes(&tone(660.0, 0.11, 0.9)).await.ok(),
            go: load_sound_from_bytes(&tone(990.0, 0.26, 0.9)).await.ok(),
            crash: load_sound_from_bytes(&crash_noise()).await.ok(),
            extend: load_sound_from_bytes(&extend_chime()).await.ok(),
            game_over: load_sound_from_bytes(&game_over_jingle()).await.ok(),
            pass: load_sound_from_bytes(&tone(1_320.0, 0.035, 0.45))
                .await
                .ok(),
            engine_bucket: None,
            muted: false,
        }
    }

    pub fn toggle_mute(&mut self) {
        self.muted = !self.muted;
        if self.muted {
            self.stop_engine();
        }
    }

    /// Keep one looping engine sample alive and shift to a higher-pitched
    /// sample as the revs rise. It is crude, but it reads as a 1974 arcade
    /// engine rather than a modern sample library.
    pub fn sync_engine(&mut self, active: bool, speed: f32, throttle: f32) {
        if self.muted || !active || self.engines.is_empty() {
            self.stop_engine();
            return;
        }

        let ratio = (speed / 240.0).clamp(0.0, 1.0);
        let bucket = ((ratio * (self.engines.len() - 1) as f32).round() as usize)
            .min(self.engines.len() - 1);
        let volume = engine_volume(throttle, ratio);

        if self.engine_bucket != Some(bucket) {
            self.stop_engine();
            play_sound(
                &self.engines[bucket],
                PlaySoundParams {
                    looped: true,
                    volume,
                },
            );
            self.engine_bucket = Some(bucket);
        }
        if let Some(current) = self.engine_bucket {
            set_sound_volume(&self.engines[current], volume);
        }
    }

    pub fn stop_engine(&mut self) {
        if let Some(bucket) = self.engine_bucket.take() {
            stop_sound(&self.engines[bucket]);
        }
    }

    pub fn countdown(&self) {
        self.play(&self.countdown, 1.0);
    }

    pub fn go(&self) {
        self.play(&self.go, 1.0);
    }

    pub fn crash(&self) {
        self.play(&self.crash, 1.0);
    }

    pub fn extend(&self) {
        self.play(&self.extend, 1.0);
    }

    pub fn game_over(&self) {
        self.play(&self.game_over, 1.0);
    }

    pub fn pass(&self) {
        self.play(&self.pass, 0.8);
    }

    fn play(&self, sound: &Option<Sound>, volume: f32) {
        if self.muted {
            return;
        }
        if let Some(sound) = sound {
            play_sound(
                sound,
                PlaySoundParams {
                    looped: false,
                    volume,
                },
            );
        }
    }
}

impl Drop for ArcadeAudio {
    fn drop(&mut self) {
        self.stop_engine();
    }
}

/// Level for the looping engine bus.
///
/// The original mix was extremely quiet on laptop speakers. Keep the idle
/// level clearly present and let throttle raise it without getting close to
/// the mixer's clipping ceiling.
fn engine_volume(throttle: f32, speed_ratio: f32) -> f32 {
    0.30 + 0.35 * throttle.clamp(0.0, 1.0) + 0.18 * speed_ratio.clamp(0.0, 1.0)
}

fn engine_loop(bucket: usize) -> Vec<u8> {
    // Whole-number frequencies guarantee a click-free one-second loop.
    let fundamental = 54.0 + bucket as f32 * 13.0;
    let mut samples = Vec::with_capacity(SAMPLE_RATE as usize);
    let mut noise = 0.0f32;
    let mut lcg = 0x1974_0055u32;

    for i in 0..SAMPLE_RATE {
        let t = i as f32 / SAMPLE_RATE as f32;
        let phase = t * fundamental * std::f32::consts::TAU;
        let wobble = 1.0 + 0.018 * (t * 3.0 * std::f32::consts::TAU).sin();

        lcg = lcg.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        let white = ((lcg >> 8) as f32 / 8_388_608.0) - 1.0;
        noise += (white - noise) * 0.09;

        let mut sample = (phase * wobble).sin() * 0.52
            + (phase * 2.0).sin() * 0.23
            + (phase * 3.0).sin() * 0.12
            + (phase * 4.0).sin() * 0.06
            + (phase * 5.0).sin() * 0.05
            + (phase * 7.0).sin() * 0.035;
        sample += noise * (0.06 + 0.03 * bucket as f32);
        // A little valve-like compression keeps the loop warm instead of
        // fizzy when several harmonics line up. The added upper harmonics
        // give the engine presence on small laptop speakers.
        sample = (sample * 1.8).tanh() * 0.55;
        samples.push(sample);
    }

    encode_wav(&samples)
}

fn tone(frequency: f32, duration: f32, volume: f32) -> Vec<u8> {
    let count = (SAMPLE_RATE as f32 * duration) as usize;
    let mut samples = Vec::with_capacity(count);
    for i in 0..count {
        let t = i as f32 / SAMPLE_RATE as f32;
        let phase = t * frequency * std::f32::consts::TAU;
        let fade = (i as f32 / count as f32 * 20.0).min(1.0)
            * ((count - i) as f32 / count as f32 * 12.0).min(1.0);
        // Slightly square-edged beep.
        let wave = phase.sin() + (phase * 2.0).sin() * 0.18;
        samples.push((wave * 0.5).tanh() * volume * fade);
    }
    encode_wav(&samples)
}

fn crash_noise() -> Vec<u8> {
    let duration = 0.85;
    let count = (SAMPLE_RATE as f32 * duration) as usize;
    let mut samples = Vec::with_capacity(count);
    let mut lcg = 0xDEAD_BEEFu32;
    let mut filtered = 0.0f32;
    for i in 0..count {
        let t = i as f32 / SAMPLE_RATE as f32;
        let fade = (1.0 - t / duration).powf(1.4);
        lcg = lcg.wrapping_mul(1_103_515_245).wrapping_add(12_345);
        let white = ((lcg >> 9) as f32 / 4_194_304.0) - 1.0;
        filtered += (white - filtered) * 0.31;
        let thud = (t * 52.0 * std::f32::consts::TAU).sin() * (1.0 - t / 0.4).max(0.0);
        samples.push(((filtered * 0.8 + thud * 0.55) * fade * 0.82).clamp(-1.0, 1.0));
    }
    encode_wav(&samples)
}

fn extend_chime() -> Vec<u8> {
    let notes = [
        (660.0, 0.0, 0.18),
        (880.0, 0.16, 0.18),
        (1_320.0, 0.32, 0.34),
    ];
    let count = (SAMPLE_RATE as f32 * 0.78) as usize;
    let mut samples = vec![0.0f32; count];
    for (frequency, offset, duration) in notes {
        let start = (offset * SAMPLE_RATE as f32) as usize;
        let note_count = (duration * SAMPLE_RATE as f32) as usize;
        for i in 0..note_count {
            if start + i >= count {
                break;
            }
            let t = i as f32 / SAMPLE_RATE as f32;
            let fade = (1.0 - i as f32 / note_count as f32).powf(1.5);
            let phase = t * frequency * std::f32::consts::TAU;
            samples[start + i] += (phase.sin() * 0.65 + (phase * 2.0).sin() * 0.2) * fade * 0.72;
        }
    }
    encode_wav(&samples)
}

fn game_over_jingle() -> Vec<u8> {
    let notes = [
        (392.0, 0.0, 0.22),
        (330.0, 0.22, 0.22),
        (262.0, 0.44, 0.25),
        (196.0, 0.74, 0.55),
    ];
    let count = (SAMPLE_RATE as f32 * 1.5) as usize;
    let mut samples = vec![0.0f32; count];
    for (frequency, offset, duration) in notes {
        let start = (offset * SAMPLE_RATE as f32) as usize;
        let note_count = (duration * SAMPLE_RATE as f32) as usize;
        for i in 0..note_count {
            if start + i >= count {
                break;
            }
            let t = i as f32 / SAMPLE_RATE as f32;
            let fade = (1.0 - i as f32 / note_count as f32).powf(1.2);
            let phase = t * frequency * std::f32::consts::TAU;
            samples[start + i] += (phase.sin() * 0.65 + (phase * 2.0).sin() * 0.22) * fade * 0.72;
        }
    }
    encode_wav(&samples)
}

fn encode_wav(samples: &[f32]) -> Vec<u8> {
    let data_len = (samples.len() * 2) as u32;
    let mut bytes = Vec::with_capacity(44 + data_len as usize);
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&(36 + data_len).to_le_bytes());
    bytes.extend_from_slice(b"WAVEfmt ");
    bytes.extend_from_slice(&16u32.to_le_bytes());
    bytes.extend_from_slice(&1u16.to_le_bytes()); // PCM
    bytes.extend_from_slice(&1u16.to_le_bytes()); // mono
    bytes.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
    bytes.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
    bytes.extend_from_slice(&2u16.to_le_bytes());
    bytes.extend_from_slice(&16u16.to_le_bytes());
    bytes.extend_from_slice(b"data");
    bytes.extend_from_slice(&data_len.to_le_bytes());
    for sample in samples {
        let value = (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wav_header_is_well_formed() {
        let bytes = tone(440.0, 0.1, 0.5);
        assert_eq!(&bytes[0..4], b"RIFF");
        assert_eq!(&bytes[8..12], b"WAVE");
        assert_eq!(&bytes[36..40], b"data");
        let length = u32::from_le_bytes(bytes[40..44].try_into().unwrap()) as usize;
        assert_eq!(length + 44, bytes.len());
    }

    #[test]
    fn engine_loop_has_expected_duration() {
        let bytes = engine_loop(2);
        assert_eq!(bytes.len(), 44 + SAMPLE_RATE as usize * 2);
    }

    #[test]
    fn engine_mix_levels_stay_audible_and_unclipped() {
        assert!(engine_volume(0.0, 0.0) >= 0.30);
        assert!(engine_volume(1.0, 1.0) <= 0.85);
        assert!(engine_volume(1.0, 1.0) > engine_volume(0.0, 0.0));
    }
}
