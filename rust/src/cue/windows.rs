//! Windows: a shared-mode render stream on the chosen endpoint, through
//! WASAPI, which converts the cue's format to whatever the device mixes at.

use super::{le_bytes, Controls, Cue};
use std::sync::mpsc::Sender;
use std::thread;
use std::time::Duration;
use wasapi::{DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat};

const POLL: Duration = Duration::from_millis(10);
/// A tenth of a second, in the 100 ns units WASAPI counts in: room enough
/// that a late wake does not run the device dry.
const BUFFER_DURATION_HNS: i64 = 1_000_000;

pub(super) fn run(
    device_id: Option<&str>,
    cue: &mut Cue,
    controls: &Controls,
    opened: &Sender<Result<(), String>>,
) -> Result<(), String> {
    // See `audio_endpoints::list` on why the result is not checked.
    let _ = wasapi::initialize_mta().ok();
    let enumerator = DeviceEnumerator::new().map_err(|e| format!("no device enumerator: {e:?}"))?;
    let device = match device_id {
        Some(id) => crate::audio_endpoints::device_by_id(&Direction::Render, id),
        None => enumerator
            .get_default_device(&Direction::Render)
            .map_err(|e| format!("{e:?}")),
    }
    .map_err(|e| format!("no such output: {e}"))?;
    let mut client = device
        .get_iaudioclient()
        .map_err(|e| format!("could not open the output: {e:?}"))?;
    let channels = usize::from(cue.channels);
    let format = WaveFormat::new(16, 16, &SampleType::Int, cue.rate as usize, channels, None);
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
    let _ = opened.send(Ok(()));

    let mut buffer = Vec::new();
    let mut ended = false;
    let result = loop {
        if controls.stopped() {
            break Ok(());
        }
        if !ended {
            let frames = match client.get_available_space_in_frames() {
                Ok(frames) => frames as usize,
                Err(e) => break Err(format!("the output went away: {e:?}")),
            };
            if frames > 0 {
                buffer.resize(frames * channels, 0);
                let written = cue.fill(&mut buffer, controls.volume());
                if written == 0 {
                    ended = true;
                } else if let Err(e) =
                    render.write_to_device(written / channels, &le_bytes(&buffer[..written]), None)
                {
                    break Err(format!("writing the cue failed: {e:?}"));
                }
            }
        }
        // Played out: nothing left in the device's buffer.
        if ended && client.get_current_padding().map_or(true, |left| left == 0) {
            break Ok(());
        }
        thread::sleep(POLL);
    };
    let _ = client.stop_stream();
    result
}
