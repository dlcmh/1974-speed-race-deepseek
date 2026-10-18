# From Loop Seams to a Live Engine

*A short history of the audio in Speed Race 1974.*

The game started with a simple rule: no assets. Every pixel is drawn by code,
and every sound should be code too. That worked beautifully for the cabinet,
the CRT and the pixel font. Audio took four attempts to get right.

This is the story of those attempts.

## The first engine: a WAV in a box

The first version generated mono 16-bit PCM at 22,050 Hz and wrapped it in an
in-memory WAV header. Macroquad's audio layer (`quad-snd`) loaded those bytes,
decoded them, resampled to 44.1 kHz stereo, and sent them to the system mixer.

The engine was six one-second loops. The loop's fundamental frequency rose with
speed, and the game switched loops when the car crossed a speed-ish threshold.
A low-priority volume curve followed throttle and speed. The one-shot effects —
countdown, crash, extension, game over — were generated the same way.

It was elegant in its own contained way. It was also wrong in a way that took
several rounds to understand.

```text
generated samples → WAV bytes → quad-snd decoder → mixer → CoreAudio
                              ↑
                    one-second buffer repeats here
```

## Act I: much too quiet

The first complaint was simple: the sounds were barely audible.

The engine sample had a healthy peak after synthesis, but it was multiplied by
a mix volume that started at about 0.045. At idle that produced a peak of only
a few percent of full scale; even at full throttle it remained tiny. The
one-shots were louder, but sparse, so the overall experience felt silent.

The first fix raised the engine bus to roughly 0.30–0.83 depending on throttle
and speed. It also added higher harmonics — a 4th harmonic and a 7th — because
a 50 Hz fundamental is mostly a rumble on a laptop speaker. The one-shots got
a smaller boost, and a regression test pinned the engine mix into a sane range.

That solved the volume. The engine was now clearly audible.

It was also clearly broken.

## Act II: the click every second

The next report was specific: there were breaks in the engine sound. Not random
interruptions — a periodic artifact, a dip followed by crackle.

The obvious suspect was the WAV loop. One second is short. The engine's tonal
components were built from whole-number frequencies, so they wrapped perfectly,
but the noise layer was filtered white noise from an LCG. The filter was
continuous inside the second; nothing made its final sample match its first.
At the wrap, the waveform jumped.

Measured at the seam, the jump was comparable to the largest normal
sample-to-sample swing — a click.

There was a second loop boundary too: every time the player crossed one of the
six speed thresholds, the game stopped the current engine sound and started the
next one. That was an even more direct discontinuity.

### First repair: crossfade all the things

The fix looked reasonable:

1. Generate a little more than one second of engine.
2. Fold the extra tail back into the start of the loop with a 40 ms crossfade.
3. Crossfade between speed buckets with an equal-power curve over 350 ms.

The seam test passed. The bucket switch no longer stopped dead. For a moment it
felt solved.

It wasn't. A new listening pass reported the same periodic dip and crackle. The
tail-fold had introduced a short amplitude dip at the start of every loop, and
the crossfade between two unrelated noise streams was doing its own subtle
things. The loop was mathematically smoother, but it was not *seamless*.

### Second repair: make the noise genuinely periodic

The next attempt removed the tail-fold entirely. Instead of filtering noise
once and crossfading the seam, the code ran a one-pole filter **circularly**
over one second of white noise. Several warm-up passes let the filter state
settle into a periodic solution. The result could wrap with no special start or
end sample; the boundary was just another sample in a continuous signal.

The engine also faded in from silence at start rather than beginning playback
abruptly on an arbitrary non-zero sample.

The tests were stronger now:

- the seam jump had to stay within 1.25× the waveform's normal maximum step;
- engine levels stayed bounded;
- the pitch still glided without restarting.

And yet — a third listening report. Still periodic. Still a dip and crackle.

At that point, patching the waveform was no longer the answer.

## Act III: stop looping

Two explanations remained. Either the loop itself was still imperfect in a way
the offline test could not see, or the audio transport was introducing
something at the boundary. We did not have ears inside the agent environment;
the human listening reports were the only reliable end-to-end test.

Rather than spend another round tuning a one-second buffer, we removed the
buffer.

The engine is now a **continuous software oscillator** rendered in a cpal
audio callback. There is no WAV, no decoder, no loop point and no speed-bucket
sample switch.

```text
cpal opens the output device
        │
        ▼
callback asks for N frames
        │
        ├── engine oscillator (phase advances forever)
        ├── one-shot voices (countdown, crash, extend, pass…)
        └── mix, clamp, write to device
```

Pitch is a smoothed floating-point value, not a choice between six recorded
loops. Speed and throttle are stored in atomics; the audio thread reads them and
glides the engine toward the new frequency and level. There is no restart, so
there is no restart click.

The one-shot effects moved into the callback too. There are eight voice slots;
each voice knows its own age, duration and envelope. The whole game now has one
audio backend instead of a WAV loader plus a separate real-time stream.

Macroquad's audio feature was disabled. This matters: it prevents two
independent audio systems from competing in the same process.

## WAV versus cpal

These are different layers, which is part of why the early debugging was
confusing.

| Thing | What it is | What it does |
| --- | --- | --- |
| WAV | A file/container format | Holds PCM samples, rate, channels, bit depth |
| quad-snd / macroquad audio | A playback/mixing layer | Decodes audio data and hands mixed samples to the OS |
| cpal | A low-level audio I/O library | Opens the device and asks our callback to fill buffers |
| CoreAudio / WASAPI / ALSA | The operating system's audio stack | Actually talks to the hardware |

A WAV is not an audio engine. It is a box of samples. If you play a one-second
box on repeat, every listener eventually hears the box's edge unless the
content is designed for it.

CPAL doesn't know what a WAV is. It just says, repeatedly, "here is an empty
buffer; fill it." That is exactly what a continuous engine needs.

## What the final engine does

The current engine (`src/audio.rs`) is deliberately small:

- a fundamental oscillator whose frequency rises with speed;
- harmonics at 2×, 3×, 4×, 5× and 7×;
- a filtered-noise layer for texture;
- a 45 ms pitch smoothing time;
- an 18 ms attack and 100 ms release on amplitude;
- one-shots rendered on demand into a fixed voice array;
- a final clamp before conversion to the device's sample format.

No loop. No sample switch. No audio files.

The tests run without an audio device:

- `engine_output_is_finite_and_bounded` drives the synth for a simulated second
  and checks that it neither diverges nor jumps;
- `engine_pitch_glides_without_restarts` checks that 0 → 240 km/h produces a
  smooth frequency sweep;
- `every_sound_ends_inside_its_buffer` checks every one-shot's envelope and
  lifetime.

## What we learned

**Test the real playback path.** A generated waveform can pass every offline
seam test and still be wrong once it enters a mixer. The screenshot bug taught
us this too: a PNG looked right while the live display was inverted. We now
treat the actual output path as the acceptance test.

**Fix causes, not symptoms.** Crossfading the WAV seam was a symptom-level fix.
It made the numbers look right without removing the looping mechanism. The
final solution was architectural: stop playing a loop.

**A format is not a transport.** WAV, cpal and CoreAudio live at different
levels. Knowing which layer owns a boundary is half the debugging.

**Keep audio headroom, but don't be timid.** The first engine mix was too quiet
by a wide margin. The final mix is calibrated against measured synth peaks and
uses a final clamp; a game should sound intentional at normal system volume.

**Human ears still matter.** Automated checks can prove continuity and
boundedness. They cannot prove that a sound is pleasant, or that a 40 ms
crossfade feels seamless. The listening reports drove every iteration here.

## The commits, if you want the archaeology

- [`b167dc5` — raised engine and effect levels](https://github.com/dlcmh/1974-speed-race-deepseek/commit/b167dc5692187939d0013557f01f753212b2a81a)
- [`3d38f35` — first seam fold, bucket crossfades](https://github.com/dlcmh/1974-speed-race-deepseek/commit/3d38f3566bef82d5c5371dc9e4bf74dfc49aa05b)
- [`c3a1a75` — circular-filtered periodic noise](https://github.com/dlcmh/1974-speed-race-deepseek/commit/c3a1a75461421d37fedb52f0dfd6ee82c8e77e11)
- [`ae566bc` — replaced the looped engine with the continuous cpal synth](https://github.com/dlcmh/1974-speed-race-deepseek/commit/ae566bc880b87c56b48bd7b5e4f63a61c96de7de)

The current implementation is in [src/audio.rs](../src/audio.rs). The broader
system design is in [ARCHITECTURE.md](ARCHITECTURE.md), and the decision record
for the final change is ADR-0012 in [DECISIONS.md](DECISIONS.md).

The engine still isn't a sample library. It is a tiny, slightly stubborn
oscillator that runs as long as the game does — which is exactly what it needed
to be.
