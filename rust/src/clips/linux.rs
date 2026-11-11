//! A chat video played by the system's GStreamer: `playbin` reads the file
//! from memory through an `appsrc`, its pictures come out of an `appsink` as
//! I420 into the clip's texture slot ([`frames`]), and its sound goes to
//! PulseAudio (PipeWire's or the real one) on the chosen output.
//!
//! `playbin` does the rest a player has to: finding a decoder for whatever
//! the file holds, from the plugins the system has — on the GPU where it has
//! one, as `vah264dec` — keeping sound and picture together, and seeking. A
//! file nothing on the system can decode fails saying so
//! ([`ClipEventKind::CannotDecode`]), and the card offers it to save.
use super::emit;
use crate::api::clips::ClipEventKind;
use crate::watching::frames::{self, Picture, WatchPlanes};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use gstreamer_video as gst_video;
use gstreamer_video::prelude::*;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};

/// What the bus is sent when the clip closes, to end its watcher.
const CLOSING: &str = "rift-clip-closing";

/// Most the source hands GStreamer at once, when it asks for "any".
const PIECE: usize = 256 * 1024;

pub(crate) struct Clip {
    playbin: gst::Element,
    bus: gst::Bus,
    watcher: Option<JoinHandle<()>>,
}

pub(super) fn init() -> Result<(), String> {
    static DONE: OnceLock<Result<(), String>> = OnceLock::new();
    DONE.get_or_init(|| gst::init().map_err(|e| format!("GStreamer: {e}")))
        .clone()
}

impl Clip {
    pub(super) fn open(
        bytes: Vec<u8>,
        texture: u64,
        output: Option<String>,
    ) -> Result<Clip, String> {
        init()?;
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
        playbin.set_property("video-sink", pictures(texture)?);
        playbin.set_property("audio-sink", sound(output)?);

        let bus = playbin
            .bus()
            .ok_or_else(|| "GStreamer gave no bus".to_string())?;
        let watcher = {
            let bus = bus.clone();
            thread::Builder::new()
                .name("rift-clip-bus".into())
                .spawn(move || watch(&bus, texture))
                .map_err(|e| format!("No thread for the video: {e}"))?
        };
        let clip = Clip {
            playbin,
            bus,
            watcher: Some(watcher),
        };
        // Paused: the first picture is drawn, and nothing plays until asked.
        clip.playbin
            .set_state(gst::State::Paused)
            .map_err(|_| "The video would not open".to_string())?;
        Ok(clip)
    }

    pub(crate) fn play(&self) -> Result<(), String> {
        self.playbin
            .set_state(gst::State::Playing)
            .map(|_| ())
            .map_err(|_| "The video would not play".to_string())
    }

    pub(crate) fn pause(&self) -> Result<(), String> {
        self.playbin
            .set_state(gst::State::Paused)
            .map(|_| ())
            .map_err(|_| "The video would not pause".to_string())
    }

    pub(crate) fn seek(&self, position_ms: u64) -> Result<(), String> {
        self.playbin
            .seek_simple(
                gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                gst::ClockTime::from_mseconds(position_ms),
            )
            .map_err(|_| "The video would not seek".to_string())
    }

    pub(crate) fn set_volume(&self, volume: f64) {
        self.playbin.set_property("volume", volume.clamp(0.0, 4.0));
    }

    /// Where it is and how long it is, in milliseconds, where GStreamer knows.
    pub(crate) fn time(&self) -> (Option<u64>, Option<u64>) {
        let position = self
            .playbin
            .query_position::<gst::ClockTime>()
            .map(|t| t.mseconds());
        let duration = self
            .playbin
            .query_duration::<gst::ClockTime>()
            .map(|t| t.mseconds());
        (position, duration)
    }
}

impl Drop for Clip {
    fn drop(&mut self) {
        // The watcher first: a stopped pipeline flushes its bus, which would
        // throw away the message that wakes it.
        let _ = self.bus.post(
            gst::message::Application::builder(gst::Structure::new_empty(CLOSING)).build(),
        );
        if let Some(watcher) = self.watcher.take() {
            let _ = watcher.join();
        }
        let _ = self.playbin.set_state(gst::State::Null);
    }
}

/// Serves [bytes] to GStreamer as a seekable file: it asks for a length at an
/// offset, and seeks by moving the offset.
pub(super) fn feed(source: &gst_app::AppSrc, bytes: Arc<Vec<u8>>) {
    source.set_size(bytes.len() as i64);
    source.set_stream_type(gst_app::AppStreamType::RandomAccess);
    source.set_format(gst::Format::Bytes);
    let offset = Arc::new(AtomicU64::new(0));
    let seek_to = offset.clone();
    source.set_callbacks(
        gst_app::AppSrcCallbacks::builder()
            .need_data(move |source, length| {
                let at = offset.load(Ordering::SeqCst) as usize;
                if at >= bytes.len() {
                    let _ = source.end_of_stream();
                    return;
                }
                let wanted = if length == u32::MAX {
                    PIECE
                } else {
                    length as usize
                };
                let end = bytes.len().min(at + wanted.max(1));
                offset.store(end as u64, Ordering::SeqCst);
                let mut buffer = gst::Buffer::from_slice(Piece {
                    bytes: bytes.clone(),
                    from: at,
                    to: end,
                });
                if let Some(buffer) = buffer.get_mut() {
                    buffer.set_offset(at as u64);
                }
                let _ = source.push_buffer(buffer);
            })
            .seek_data(move |_, to| {
                seek_to.store(to, Ordering::SeqCst);
                true
            })
            .build(),
    );
}

/// A run of the file's bytes, lent to GStreamer without a copy.
struct Piece {
    bytes: Arc<Vec<u8>>,
    from: usize,
    to: usize,
}

impl AsRef<[u8]> for Piece {
    fn as_ref(&self) -> &[u8] {
        &self.bytes[self.from..self.to]
    }
}

/// The picture side: converted to I420, which the runner draws from memory,
/// and delivered to [texture]'s slot when its time comes (the sink keeps
/// time with the sound).
fn pictures(texture: u64) -> Result<gst::Element, String> {
    // A phone's portrait video is stored on its side with a tag to turn it;
    // `videoflip` reads the tag. Without the plugin it plays as stored.
    let bin = gst::parse::bin_from_description(
        "videoconvert ! videoflip video-direction=auto ! appsink name=pictures",
        true,
    )
    .or_else(|_| gst::parse::bin_from_description("videoconvert ! appsink name=pictures", true))
    .map_err(|e| format!("GStreamer cannot convert pictures: {e}"))?;
    let sink = bin
        .by_name("pictures")
        .and_then(|e| e.downcast::<gst_app::AppSink>().ok())
        .ok_or_else(|| "GStreamer gave no picture sink".to_string())?;
    sink.set_caps(Some(
        &gst_video::VideoCapsBuilder::new()
            .format(gst_video::VideoFormat::I420)
            .build(),
    ));
    sink.set_max_buffers(1);
    sink.set_drop(true);
    let size = Arc::new(Mutex::new((0u32, 0u32)));
    let shown = {
        let size = size.clone();
        move |sample: gst::Sample| show(texture, &sample, &size)
    };
    let prerolled = shown.clone();
    sink.set_callbacks(
        gst_app::AppSinkCallbacks::builder()
            .new_sample(move |sink| {
                if let Ok(sample) = sink.pull_sample() {
                    shown(sample);
                }
                Ok(gst::FlowSuccess::Ok)
            })
            // The first picture while paused, and the one a paused seek lands
            // on.
            .new_preroll(move |sink| {
                if let Ok(sample) = sink.pull_preroll() {
                    prerolled(sample);
                }
                Ok(gst::FlowSuccess::Ok)
            })
            .build(),
    );
    Ok(bin.upcast())
}

/// Hands [sample]'s picture to the runner, and tells the app its shape when
/// that is new.
fn show(texture: u64, sample: &gst::Sample, size: &Mutex<(u32, u32)>) {
    let (Some(buffer), Some(caps)) = (sample.buffer_owned(), sample.caps()) else {
        return;
    };
    let Ok(info) = gst_video::VideoInfo::from_caps(caps) else {
        return;
    };
    let colour = info.colorimetry();
    let matrix = match colour.matrix() {
        gst_video::VideoColorMatrix::Bt709 => 1,
        gst_video::VideoColorMatrix::Bt2020 => 2,
        _ => 0,
    };
    let full_range = u32::from(colour.range() == gst_video::VideoColorRange::Range0_255);
    // Shown size: a picture with non-square pixels is stretched to look right.
    let par = info.par();
    let shown_width = if par.numer() > 0 && par.denom() > 0 {
        (info.width() as u64 * par.numer() as u64 / par.denom() as u64) as u32
    } else {
        info.width()
    };
    let Ok(frame) = gst_video::VideoFrame::from_buffer_readable(buffer, &info) else {
        return;
    };
    {
        let mut last = size.lock().unwrap_or_else(|e| e.into_inner());
        if *last != (shown_width, info.height()) {
            *last = (shown_width, info.height());
            emit(
                texture,
                ClipEventKind::PictureSize,
                shown_width,
                info.height(),
                String::new(),
            );
        }
    }
    frames::deliver(
        texture,
        GstPicture {
            frame,
            matrix,
            full_range,
        },
    );
}

/// A decoded picture, mapped for reading until the runner hands it back.
struct GstPicture {
    frame: gst_video::VideoFrame<gst_video::video_frame::Readable>,
    matrix: u32,
    full_range: u32,
}

impl Picture for GstPicture {
    fn planes(&self) -> WatchPlanes {
        let f = &self.frame;
        let plane = |i: u32| {
            f.plane_data(i)
                .map(|p| p.as_ptr())
                .unwrap_or(std::ptr::null())
        };
        let stride = f.plane_stride();
        WatchPlanes {
            y: plane(0),
            u: plane(1),
            v: plane(2),
            stride_y: stride[0] as u32,
            stride_u: stride[1] as u32,
            stride_v: stride[2] as u32,
            matrix: self.matrix,
            full_range: self.full_range,
            ..WatchPlanes::sized(f.width(), f.height())
        }
    }
}

/// The sound side: PulseAudio on [output] where it is there, else whatever
/// GStreamer finds. [output] is the app's choice as WebRTC lists it, which
/// names a sink by its description.
fn sound(output: Option<String>) -> Result<gst::Element, String> {
    if let Ok(pulse) = gst::ElementFactory::make("pulsesink").build() {
        let sink = output.filter(|d| !d.is_empty()).and_then(|id| {
            let mut connection = crate::pulse::Connection::open("rift-clip")?;
            crate::pulse::sink_for(&mut connection, Some(&id))
        });
        if let Some(sink) = sink {
            pulse.set_property("device", sink);
        }
        return Ok(pulse);
    }
    gst::ElementFactory::make("autoaudiosink")
        .build()
        .map_err(|_| "GStreamer has no sound output".to_string())
}

/// Reads the clip's bus until it closes: the end, and failures.
fn watch(bus: &gst::Bus, texture: u64) {
    while let Some(message) = bus.timed_pop(gst::ClockTime::NONE) {
        match message.view() {
            gst::MessageView::Application(a)
                if a.structure().is_some_and(|s| s.name() == CLOSING) =>
            {
                return;
            }
            gst::MessageView::Eos(_) => {
                emit(texture, ClipEventKind::Ended, 0, 0, String::new());
            }
            gst::MessageView::Error(e) => {
                let error = e.error();
                let missing = error.matches(gst::StreamError::CodecNotFound)
                    || error.matches(gst::CoreError::MissingPlugin)
                    || error.matches(gst::StreamError::TypeNotFound);
                log::warn!("Chat video failed: {}", error.message());
                let kind = if missing {
                    ClipEventKind::CannotDecode
                } else {
                    ClipEventKind::Failed
                };
                emit(texture, kind, 0, 0, error.message().to_string());
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::watching::frames::{rift_watch_frame_lock, rift_watch_frame_unlock, WatchPlanes};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::Duration;

    static MARKS: AtomicU64 = AtomicU64::new(0);

    unsafe extern "C" fn mark(_texture: u64) {
        MARKS.fetch_add(1, Ordering::SeqCst);
    }

    /// Plays a real file from memory, its sound to a test output:
    ///
    /// ```text
    /// RIFT_CLIP_TEST=<a video> RIFT_CLIP_TEST_OUTPUT=<a sink> \
    ///     cargo test --release live_clip -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "needs a video and a test output; see above"]
    fn live_clip_plays_seeks_and_closes() {
        let bytes = std::fs::read(std::env::var("RIFT_CLIP_TEST").unwrap()).unwrap();
        let output = std::env::var("RIFT_CLIP_TEST_OUTPUT").ok();
        let texture = 9001;
        super::super::open(bytes, texture, mark, output).unwrap();
        std::thread::sleep(Duration::from_millis(500));
        let paused = MARKS.load(Ordering::SeqCst);
        assert!(paused >= 1, "the first picture is shown while paused");

        let mut planes = WatchPlanes::sized(0, 0);
        assert_eq!(unsafe { rift_watch_frame_lock(texture, &mut planes) }, 1);
        println!(
            "picture {}x{}, matrix {}",
            planes.width, planes.height, planes.matrix
        );
        assert!(planes.width > 0 && !planes.y.is_null() && !planes.v.is_null());
        rift_watch_frame_unlock(texture, 1);

        super::super::with(texture, |c| c.play()).unwrap().unwrap();
        std::thread::sleep(Duration::from_millis(1000));
        let played = MARKS.load(Ordering::SeqCst) - paused;
        println!("{played} pictures in a second of play");
        assert!(played >= 10);

        super::super::with(texture, |c| c.seek(2500))
            .unwrap()
            .unwrap();
        std::thread::sleep(Duration::from_millis(200));
        let (position, duration) = super::super::with(texture, |c| c.time()).unwrap();
        println!("after the seek: {position:?} of {duration:?}");
        assert!(position.unwrap() >= 2500);

        super::super::close(texture);
        let after = MARKS.load(Ordering::SeqCst);
        std::thread::sleep(Duration::from_millis(300));
        assert_eq!(
            MARKS.load(Ordering::SeqCst),
            after,
            "nothing marked once closed"
        );
    }
}
