//! A sound decoded whole by the system's GStreamer, for the cue player to
//! play on a device it opens (`crate::cue`): a soundboard clip, in whatever
//! format it was uploaded. Read from memory as a chat video is
//! ([`super::linux::feed`]), and turned into one fixed shape so the player
//! needs to know nothing of where it came from.
use super::linux::{feed, init};
use super::poster_linux::first_error;
use super::source::Source;
use super::Pcm;
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use std::sync::Arc;

/// What every sound comes out as. Two channels whatever the file, so a mono
/// clip plays in both ears, and one rate, so the cue player opens the device
/// the same way each time.
const CHANNELS: u16 = 2;
const RATE: u32 = 48_000;

/// How long one piece of decoded sound may take to arrive. Decoding is far
/// faster than playing, so this is only the bound on a file that never ends.
const PATIENCE: gst::ClockTime = gst::ClockTime::from_seconds(10);

/// [file]'s sound, at most [max_ms] of it.
pub(super) fn decode(file: Arc<Source>, max_ms: u32) -> Result<Pcm, String> {
    init()?;
    let playbin = gst::ElementFactory::make("playbin")
        .property("uri", "appsrc://")
        .build()
        .map_err(|_| "GStreamer has no playbin".to_string())?;
    let feeding = file.clone();
    playbin.connect("source-setup", false, move |args| {
        if let Ok(source) = args[1].get::<gst::Element>() {
            if let Ok(source) = source.downcast::<gst_app::AppSrc>() {
                feed(&source, feeding.clone());
            }
        }
        None
    });
    // Not synced to the clock: the whole file as fast as it decodes.
    let bin = gst::parse::bin_from_description(
        &format!(
            "audioconvert ! audioresample ! \
             audio/x-raw,format=S16LE,layout=interleaved,channels={CHANNELS},rate={RATE} ! \
             appsink name=pcm sync=false"
        ),
        true,
    )
    .map_err(|e| format!("GStreamer cannot decode a sound: {e}"))?;
    let sink = bin
        .by_name("pcm")
        .and_then(|e| e.downcast::<gst_app::AppSink>().ok())
        .ok_or_else(|| "GStreamer gave no sound sink".to_string())?;
    playbin.set_property("audio-sink", &bin);
    if let Ok(nothing) = gst::ElementFactory::make("fakesink").build() {
        playbin.set_property("video-sink", nothing);
    }

    let most = most_samples(max_ms);
    let result = (|| {
        playbin
            .set_state(gst::State::Playing)
            .map_err(|_| "The sound would not open".to_string())?;
        let mut samples: Vec<i16> = Vec::new();
        while samples.len() < most {
            let Some(sample) = sink.try_pull_sample(PATIENCE) else {
                if sink.is_eos() {
                    break;
                }
                return Err(first_error(&playbin, "The sound did not decode in time"));
            };
            let Some(buffer) = sample.buffer() else {
                continue;
            };
            let map = buffer
                .map_readable()
                .map_err(|_| "The sound could not be read".to_string())?;
            samples.extend(
                map.as_slice()
                    .chunks_exact(2)
                    .map(|b| i16::from_le_bytes([b[0], b[1]])),
            );
        }
        samples.truncate(most);
        if samples.is_empty() {
            return Err("No sound in the file".to_string());
        }
        Ok(Pcm {
            samples,
            channels: CHANNELS,
            rate: RATE,
        })
    })();
    file.close();
    let _ = playbin.set_state(gst::State::Null);
    result
}

/// How many samples [max_ms] of sound is, in whole frames.
fn most_samples(max_ms: u32) -> usize {
    (u64::from(RATE) * u64::from(max_ms) / 1000) as usize * usize::from(CHANNELS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_cap_is_whole_frames() {
        assert_eq!(most_samples(1000), 96_000);
        assert_eq!(most_samples(0), 0);
        assert_eq!(most_samples(1) % 2, 0);
    }

    /// ```text
    /// RIFT_SOUND_TEST=<a sound file> cargo test --release live_sound -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "needs a sound file; see above"]
    fn live_sound_decodes_to_stereo() {
        let bytes = std::fs::read(std::env::var("RIFT_SOUND_TEST").unwrap()).unwrap();
        let started = std::time::Instant::now();
        let pcm = decode(Source::memory(bytes), 30_000).unwrap();
        let seconds = pcm.samples.len() as f64 / 2.0 / f64::from(pcm.rate);
        println!("{seconds:.2} s of sound in {:?}", started.elapsed());
        assert_eq!((pcm.channels, pcm.rate), (2, 48_000));
        assert!(pcm.samples.iter().any(|&s| s != 0), "not all silence");
    }
}
