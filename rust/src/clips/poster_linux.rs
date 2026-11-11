//! A chat video's first picture, as a small JPEG for its card to show
//! before it plays: GStreamer decodes the file from memory as the player
//! does ([`super::linux`]), turns it upright, shrinks it and encodes the one
//! picture, and stops.
use super::linux::{feed, init};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use std::sync::Arc;

/// How long the first picture may take before there is no poster.
const PATIENCE: gst::ClockTime = gst::ClockTime::from_seconds(10);

/// [bytes]' first picture, its longer side at most [longest], as a JPEG.
pub(crate) fn poster(bytes: Vec<u8>, longest: u32) -> Result<Vec<u8>, String> {
    init()?;
    let longest = longest.clamp(16, 4096);
    let playbin = gst::ElementFactory::make("playbin")
        .property("uri", "appsrc://")
        .build()
        .map_err(|_| "GStreamer has no playbin".to_string())?;
    let bytes = Arc::new(bytes);
    playbin.connect("source-setup", false, move |args| {
        if let Ok(source) = args[1].get::<gst::Element>() {
            if let Ok(source) = source.downcast::<gst_app::AppSrc>() {
                feed(&source, bytes.clone());
            }
        }
        None
    });
    // `videoscale` keeps the picture's shape when only a bound is given.
    let bin = gst::parse::bin_from_description(
        &format!(
            "videoconvert ! videoflip video-direction=auto ! videoscale ! \
             video/x-raw,width=[1,{longest}],height=[1,{longest}],pixel-aspect-ratio=1/1 ! \
             jpegenc quality=80 ! appsink name=poster"
        ),
        true,
    )
    .map_err(|e| format!("GStreamer cannot make a poster: {e}"))?;
    let sink = bin
        .by_name("poster")
        .and_then(|e| e.downcast::<gst_app::AppSink>().ok())
        .ok_or_else(|| "GStreamer gave no poster sink".to_string())?;
    playbin.set_property("video-sink", &bin);
    // The sound is not wanted, but a pipeline with nowhere to put it waits.
    if let Ok(silent) = gst::ElementFactory::make("fakesink").build() {
        playbin.set_property("audio-sink", silent);
    }
    let result = (|| {
        playbin
            .set_state(gst::State::Paused)
            .map_err(|_| "The video would not open".to_string())?;
        let sample = sink
            .try_pull_preroll(PATIENCE)
            .ok_or_else(|| first_error(&playbin))?;
        let buffer = sample
            .buffer()
            .ok_or_else(|| "No first picture".to_string())?;
        let map = buffer
            .map_readable()
            .map_err(|_| "The first picture could not be read".to_string())?;
        Ok(map.as_slice().to_vec())
    })();
    let _ = playbin.set_state(gst::State::Null);
    result
}

/// Why no picture came: the bus's error, where there is one.
fn first_error(playbin: &gst::Element) -> String {
    playbin
        .bus()
        .and_then(|bus| bus.pop_filtered(&[gst::MessageType::Error]))
        .and_then(|message| match message.view() {
            gst::MessageView::Error(e) => Some(e.error().message().to_string()),
            _ => None,
        })
        .unwrap_or_else(|| "No first picture in time".to_string())
}

#[cfg(test)]
mod tests {
    /// ```text
    /// RIFT_CLIP_TEST=<a video> cargo test --release live_poster -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "needs a video; see above"]
    fn live_poster_is_a_small_jpeg() {
        let path = std::env::var("RIFT_CLIP_TEST").unwrap();
        let bytes = std::fs::read(&path).unwrap();
        let started = std::time::Instant::now();
        let jpeg = super::poster(bytes, 440).unwrap();
        println!("{} bytes in {:?}", jpeg.len(), started.elapsed());
        assert_eq!(&jpeg[..2], &[0xff, 0xd8], "a JPEG");
        if let Ok(out) = std::env::var("RIFT_POSTER_OUT") {
            std::fs::write(out, &jpeg).unwrap();
        }
    }
}
