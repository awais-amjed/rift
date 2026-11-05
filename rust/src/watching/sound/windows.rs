//! Windows: a stereo render stream on the chosen output through WASAPI, in
//! shared mode, which converts 48 kHz 16-bit stereo to whatever the device
//! mixes at, the way the mic test plays you back.

use super::drift::Drift;
use super::{output_changes, playable, Gain, CHANNELS, SAMPLE_RATE};
use crate::cue::le_bytes;
use std::sync::mpsc::Receiver;
use wasapi::{
    AudioClient, AudioRenderClient, DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat,
};

pub(crate) const PLAYS: bool = true;

/// The most the output may hold ahead of what is heard, in samples: 80 ms.
/// What it does hold is about 35 (`CUSHION_SAMPLES`, `Drift`). Counted from the
/// stream's padding rather than set as its buffer, which Windows' engine
/// empties in uneven gulps: the mic test's small buffer was often full when the
/// next packet came, and the voice was cut.
const HELD_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize * 80 / 1000;

/// Silence put ahead of the sound when the output holds nothing, at the start
/// and after it ran dry: 30 ms. Without it a frame is played the moment it
/// lands, the output never holds more than one, and one that arrives late is
/// a click (the mic test's lesson).
const CUSHION_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize * 30 / 1000;

/// What the output should stay under, on average: 40 ms.
const STEADY_SAMPLES: usize = (SAMPLE_RATE * CHANNELS) as usize * 40 / 1000;

/// One second, in the 100 ns units WASAPI counts in: the buffer's size, of
/// which no more than [`HELD_SAMPLES`] is used.
const BUFFER_DURATION_HNS: i64 = 10_000_000;

/// Failures in a row, of an output that opened, before giving up on the
/// sound: one is a device unplugged or reset, and the next frame opens the
/// output again.
const FAILURES_TO_GIVE_UP: u32 = 3;

pub(super) fn run(frames: Receiver<Vec<i16>>, gain: &Gain) -> Result<(), String> {
    // See `audio_endpoints::list` on why the result is not checked.
    let _ = wasapi::initialize_mta().ok();
    let mut output: Option<Output> = None;
    let ended = play_until_fed(&frames, gain, &mut output);
    if let Some(playing) = output {
        playing.stop();
    }
    ended
}

/// Plays each frame until the feed ends (Ok), or the output will not open
/// or keeps failing.
fn play_until_fed(
    frames: &Receiver<Vec<i16>>,
    gain: &Gain,
    output: &mut Option<Output>,
) -> Result<(), String> {
    let mut failures = 0;
    // Each frame is 10 ms; the feed ends, and with it this, when the share
    // stops playing.
    while let Ok(frame) = frames.recv() {
        if output.as_ref().map(|output| output.change) != Some(output_changes()) {
            if let Some(old) = output.take() {
                old.stop();
            }
            let (change, device) = super::output();
            *output = Some(Output::open(change, device.as_deref())?);
        }
        let Some(playing) = output.as_mut() else {
            continue;
        };
        match playing.play(&frame, gain.get()) {
            Ok(()) => failures = 0,
            Err(message) => {
                log::warn!("watching: playing the sound failed: {message}");
                failures += 1;
                if failures >= FAILURES_TO_GIVE_UP {
                    return Err(format!("playing the sound failed: {message}"));
                }
                if let Some(old) = output.take() {
                    old.stop();
                }
            }
        }
    }
    Ok(())
}

/// A started render stream, and the output change it was opened for.
struct Output {
    change: u64,
    client: AudioClient,
    render: AudioRenderClient,
    drift: Drift,
}

impl Output {
    /// On the output WebRTC lists as `device_id` (the default when None, or
    /// when it is not there any more), 48 kHz 16-bit stereo, which shared mode
    /// converts to the device's own format.
    fn open(change: u64, device_id: Option<&str>) -> Result<Output, String> {
        let chosen = device_id.and_then(|id| {
            let device = crate::audio_endpoints::device_by_id(&Direction::Render, id).ok();
            if device.is_none() {
                log::warn!("watching: no output {id}, playing on the default");
            }
            device
        });
        let device = match chosen {
            Some(device) => device,
            None => DeviceEnumerator::new()
                .and_then(|enumerator| enumerator.get_default_device(&Direction::Render))
                .map_err(|e| format!("no output: {e:?}"))?,
        };
        let mut client = device
            .get_iaudioclient()
            .map_err(|e| format!("could not open the output: {e:?}"))?;
        let format = WaveFormat::new(
            16,
            16,
            &SampleType::Int,
            SAMPLE_RATE as usize,
            CHANNELS as usize,
            None,
        );
        let mode = StreamMode::PollingShared {
            autoconvert: true,
            buffer_duration_hns: BUFFER_DURATION_HNS,
        };
        client
            .initialize_client(&format, &Direction::Render, &mode)
            .map_err(|e| format!("the output refused the format: {e:?}"))?;
        let render = client
            .get_audiorenderclient()
            .map_err(|e| format!("no render client: {e:?}"))?;
        client
            .start_stream()
            .map_err(|e| format!("the output would not start: {e:?}"))?;
        log::info!(
            "watching: playing the sound on {}",
            device.get_friendlyname().unwrap_or_default()
        );
        Ok(Output {
            change,
            client,
            render,
            drift: Drift::new(STEADY_SAMPLES),
        })
    }

    fn play(&mut self, frame: &[i16], gain: f32) -> Result<(), String> {
        let queued = self
            .client
            .get_current_padding()
            .map_err(|e| format!("{e:?}"))? as usize
            * CHANNELS as usize;
        let frame = self.drift.adjust(frame, queued);
        let written = to_write(&frame, queued, gain);
        if written.is_empty() {
            return Ok(());
        }
        self.render
            .write_to_device(written.len() / CHANNELS as usize, &le_bytes(&written), None)
            .map_err(|e| format!("{e:?}"))
    }

    fn stop(self) {
        let _ = self.client.stop_stream();
    }
}

/// Room for more, in samples, while the output holds `queued` of `held`.
fn room(queued: usize, held: usize) -> usize {
    held.saturating_sub(queued)
}

/// What to write for `frame` while the output holds `queued` samples, at
/// `gain`: a cushion of silence first if it ran dry, then as much of the
/// frame as fits, in whole frames.
fn to_write(frame: &[i16], queued: usize, gain: f32) -> Vec<i16> {
    let room = room(queued, HELD_SAMPLES);
    let cushion = if queued == 0 {
        CUSHION_SAMPLES.min(room)
    } else {
        0
    };
    let mut written = vec![0; cushion];
    written.extend(playable(frame, room - cushion, gain));
    written
}

#[cfg(test)]
mod tests {
    use super::*;

    const FRAME: usize = (SAMPLE_RATE * CHANNELS) as usize / 100;

    fn frame() -> Vec<i16> {
        (0..FRAME as i16).map(|i| i + 1).collect()
    }

    #[test]
    fn room_is_what_is_left_of_the_hold() {
        assert_eq!(room(0, HELD_SAMPLES), HELD_SAMPLES);
        assert_eq!(room(1000, HELD_SAMPLES), HELD_SAMPLES - 1000);
        assert_eq!(room(HELD_SAMPLES * 2, HELD_SAMPLES), 0);
    }

    #[test]
    fn an_empty_output_gets_the_cushion_then_the_frame() {
        let written = to_write(&frame(), 0, 1.0);
        assert_eq!(written.len(), CUSHION_SAMPLES + FRAME);
        assert!(written[..CUSHION_SAMPLES].iter().all(|&s| s == 0));
        assert_eq!(written[CUSHION_SAMPLES..], frame()[..]);
    }

    #[test]
    fn a_full_output_gets_nothing() {
        assert!(to_write(&frame(), HELD_SAMPLES, 1.0).is_empty());
        assert!(to_write(&frame(), HELD_SAMPLES + 480, 1.0).is_empty());
    }

    #[test]
    fn a_part_full_output_gets_whole_frames_of_what_fits() {
        // Room for 101 samples: 50 left-and-right pairs, no cushion.
        let written = to_write(&frame(), HELD_SAMPLES - 101, 1.0);
        assert_eq!(written, frame()[..100]);
        // Room for the whole frame: all of it, no cushion.
        assert_eq!(to_write(&frame(), HELD_SAMPLES - FRAME, 1.0), frame());
    }

    #[test]
    fn a_frame_fits_while_the_output_is_steady() {
        // The end of a frame that does not fit is cut off, which is a click.
        const SWING: usize = 2 * FRAME;
        const { assert!(STEADY_SAMPLES + SWING + FRAME <= HELD_SAMPLES) };
    }

    #[test]
    fn the_cushion_and_a_frame_fit_the_hold() {
        const { assert!(CUSHION_SAMPLES + FRAME <= HELD_SAMPLES) };
        assert_eq!(CUSHION_SAMPLES % CHANNELS as usize, 0, "left stays left");
    }

    #[test]
    fn the_frame_is_played_at_the_gain() {
        let written = to_write(&[100, -100], 0, 0.5);
        assert_eq!(written[CUSHION_SAMPLES..], [50, -50]);
    }
}
