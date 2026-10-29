//! A Wayland share on Rift's own PipeWire stream (`docs/gpu-codecs/STEP2_LINUX.md`):
//! the portal from Rust (`portal.rs`), the stream in Rift's FFmpeg library
//! (`pw_stream.rs`), and each picture to the GPU encoder as the compositor's
//! DMA-BUF where the encoder takes one, or from memory for VP9 and NVENC.
//! When any of it refuses, the share runs on libwebrtc's capturer as before.
use super::capture::{CaptureRequest, Command, Feed, Progress, VideoSlot};
use super::encoder::dmabuf_render_node;
use super::frames::{now_us, Converter};
use super::gpu_feed::{GpuFeed, Picture};
use super::latest::{self, Taker};
use super::portal::{self, PortalError, PortalKind, PortalSession};
use super::pw_stream::{self, PwBuffers, PwEvent, PwPicture, PwStream};
use super::resolution::Size;
use crate::api::screenshare::types::ScreenshareEvent;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, TryRecvError};
use std::sync::{Arc, Mutex, Weak};
use std::thread;
use std::time::Duration;
use tokio::sync::mpsc::UnboundedSender;

/// How often the capture thread looks for a stop, an ended stream or a new
/// rate. The pictures themselves never wait on it.
const POLL: Duration = Duration::from_millis(100);

/// Whether this is a Wayland session, by the rule libwebrtc's own capturer
/// goes by, so a share Rift's stream refuses meets the capturer it would have
/// had anyway.
pub(crate) fn on_wayland() -> bool {
    on_wayland_from(
        std::env::var("WAYLAND_DISPLAY").ok().as_deref(),
        std::env::var("XDG_SESSION_TYPE").ok().as_deref(),
    )
}

fn on_wayland_from(wayland_display: Option<&str>, session_type: Option<&str>) -> bool {
    wayland_display.is_some_and(|display| !display.is_empty()) && session_type == Some("wayland")
}

/// The buffers `feed` can use: DMA-BUFs for a GPU encoder that imports them,
/// memory for the rest.
pub(crate) fn buffers_for(feed: &Feed) -> PwBuffers {
    wanted_buffers(match feed {
        Feed::Raw(_) => None,
        Feed::Gpu(gpu) => Some(gpu.takes_dmabuf()),
    })
}

/// The buffers a feed wants: `None` for the raw path, else whether its GPU
/// encoder takes a DMA-BUF.
fn wanted_buffers(gpu_takes_dmabuf: Option<bool>) -> PwBuffers {
    match gpu_takes_dmabuf {
        Some(true) => PwBuffers::DmaBuf,
        Some(false) | None => PwBuffers::Memory,
    }
}

/// How a share went on Rift's stream.
pub(super) enum Handoff {
    /// It ran, or failed in a way libwebrtc's capturer would too (the
    /// picker closed), and is over.
    Done,
    /// Not on Rift's stream: libwebrtc's capturer takes the request.
    Fallback(CaptureRequest),
}

/// Runs the share on Rift's stream until a stop or until the stream ends.
/// Portal calls go on `runtime`, the app's own: ashpd's one D-Bus connection
/// is driven by the runtime that opened it.
pub(super) fn run(
    mut request: CaptureRequest,
    runtime: Option<tokio::runtime::Handle>,
    fps: &AtomicU32,
    progress: &UnboundedSender<Progress>,
    slot: &VideoSlot,
    command_rx: &mpsc::Receiver<Command>,
) -> Handoff {
    if !on_wayland() {
        return Handoff::Fallback(request);
    }
    let Some(runtime) = runtime else {
        log::info!("capture: no runtime for the portal; libwebrtc's capturer");
        return Handoff::Fallback(request);
    };
    if !pw_stream::available() {
        log::info!("capture: FFmpeg's library has no PipeWire stream; libwebrtc's capturer");
        return Handoff::Fallback(request);
    }
    let kind = match request.source_type {
        DesktopCaptureSourceType::Window => PortalKind::Window,
        _ => PortalKind::Screen,
    };
    let _ = progress.send(Progress::Picking);
    let opened = runtime.block_on(open_portal(
        kind,
        request.portal_choice.as_deref(),
        request.capture_cursor,
    ));
    let session = match opened {
        Ok(session) => session,
        Err(PortalError::Cancelled) => {
            let _ = progress.send(Progress::Failed(
                "The desktop's picker was closed without a choice".to_string(),
            ));
            return Handoff::Done;
        }
        Err(PortalError::Unavailable(reason)) => {
            log::info!("capture: the portal refused ({reason}); libwebrtc's capturer");
            return Handoff::Fallback(request);
        }
    };
    // Stopped while the picker was up.
    if !matches!(command_rx.try_recv(), Err(TryRecvError::Empty)) {
        return Handoff::Done;
    }
    let _ = progress.send(Progress::Picked);

    // Only Rift's stream reports a pause on Linux, so libwebrtc's capturer
    // loses nothing if the stream refuses.
    let on_paused = request.on_paused.take();
    let arrived = Arc::new(AtomicBool::new(false));
    let ended = Arc::new(Mutex::new(None::<String>));
    let (put, pictures) = latest::channel::<PwPicture>();
    let first = Mutex::new(Some(progress.clone()));
    let seen = arrived.clone();
    let sink = move |picture: PwPicture| {
        if !seen.swap(true, Ordering::Relaxed) {
            if let Some(tx) = first.lock().unwrap().take() {
                let _ = tx.send(Progress::FirstFrame(picture.size()));
            }
        }
        // The picture it replaced, or this one once nobody takes them,
        // goes back to the compositor here.
        drop(put.put(picture));
    };
    let events = {
        let arrived = arrived.clone();
        let ended = ended.clone();
        let paused = AtomicBool::new(false);
        let report = move |now: bool| {
            if paused.swap(now, Ordering::Relaxed) != now {
                if let Some(on_paused) = &on_paused {
                    on_paused(now);
                }
            }
        };
        Box::new(move |event| match event {
            PwEvent::Streaming => report(false),
            // GNOME pauses a stream before its first picture too, which is
            // not a window anybody minimised.
            PwEvent::Paused if arrived.load(Ordering::Relaxed) => report(true),
            PwEvent::Paused => {}
            PwEvent::Ended(reason) => *ended.lock().unwrap() = Some(reason),
        })
    };
    let render_node = dmabuf_render_node();
    // Memory first: the feed is not attached until the first picture has
    // said the size, and a GPU feed takes a memory picture where the raw
    // path cannot take a DMA-BUF. A GPU feed switches the stream over.
    let rate = fps.load(Ordering::Relaxed);
    let stream = match PwStream::open(
        &session,
        rate,
        render_node.as_deref(),
        PwBuffers::Memory,
        sink,
        events,
    ) {
        Ok(stream) => Arc::new(stream),
        Err(reason) => {
            log::warn!(
                "capture: Rift's PipeWire stream did not open ({reason}); libwebrtc's capturer"
            );
            return Handoff::Fallback(request);
        }
    };
    log::info!(
        "capture: on Rift's PipeWire stream ({}), DMA-BUFs for {}",
        session
            .size
            .map_or("size not given".to_string(), |s| format!(
                "{}x{}",
                s.width, s.height
            )),
        render_node.as_deref().unwrap_or("no GPU (memory only)")
    );

    let processing = slot.clone();
    let controls = Arc::downgrade(&stream);
    let _processing = thread::Builder::new()
        .name("share-frames".to_string())
        .spawn(move || process(pictures, processing, controls))
        .expect("no processing thread");

    watch(
        &stream, &session, &ended, &arrived, fps, rate, progress, command_rx,
    );
    // The stream first, which closes the processing thread's mailbox; the
    // portal session after it.
    drop(stream);
    drop(session);
    log::info!("capture: thread exiting");
    Handoff::Done
}

/// The portal session for a share. A window's pick was made in Dart's
/// picker and is not kept again: GNOME forgets a pick once it is used, and
/// Dart forgets it on KDE (`WindowSharePortal.forget`). A screen is picked
/// here each time, as libwebrtc's capturer asked.
async fn open_portal(
    kind: PortalKind,
    window_choice: Option<&str>,
    cursor: bool,
) -> Result<PortalSession, PortalError> {
    // A live test restores the screen from the token `pw_stream`'s tests use.
    #[cfg(test)]
    if let (PortalKind::Screen, Some(file)) = (kind, std::env::var_os("RIFT_PORTAL_TOKEN")) {
        let token = std::fs::read_to_string(&file).unwrap();
        let session = portal::open(kind, Some(token.trim()), cursor, true).await?;
        if let Some(renewed) = &session.restore_token {
            std::fs::write(&file, renewed).unwrap();
        }
        return Ok(session);
    }
    portal::open(kind, window_choice, cursor, false).await
}

/// The capture thread's part once pictures flow: waits for a stop, ends the
/// share when the stream ends, and passes on a new rate.
#[allow(clippy::too_many_arguments)]
fn watch(
    stream: &PwStream,
    session: &PortalSession,
    ended: &Mutex<Option<String>>,
    arrived: &AtomicBool,
    fps: &AtomicU32,
    mut rate: u32,
    progress: &UnboundedSender<Progress>,
    command_rx: &mpsc::Receiver<Command>,
) {
    loop {
        match command_rx.recv_timeout(POLL) {
            Ok(Command::Terminate) | Err(RecvTimeoutError::Disconnected) => return,
            Err(RecvTimeoutError::Timeout) => {}
        }
        let stream_ended = ended.lock().unwrap().take();
        if let Some(reason) = ended_by(stream_ended, session.closed()) {
            if arrived.load(Ordering::Relaxed) {
                log::info!("capture: the share is over ({reason}), ending it");
                crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
            } else {
                let _ = progress.send(Progress::Failed(reason));
            }
            return;
        }
        let now = fps.load(Ordering::Relaxed);
        if now != rate {
            log::info!("capture: now at most {now} fps");
            stream.set_max_fps(now);
            rate = now;
        }
    }
}

/// Why the desktop ended a share whose stream had not.
const SESSION_CLOSED: &str = "The desktop ended the share";

/// What ends a share on Rift's stream, if anything has: the stream ending,
/// or the portal session closing, which is all GNOME does when the shared
/// window closes (the stream only pauses). libwebrtc's capturer ends the
/// share on the same signal.
fn ended_by(stream_ended: Option<String>, session_closed: bool) -> Option<String> {
    stream_ended.or_else(|| session_closed.then(|| SESSION_CLOSED.to_string()))
}

/// The processing thread: each picture to its feed, in the buffers the feed
/// can use, asking the stream for those whenever the feed changes.
fn process(pictures: Taker<PwPicture>, slot: VideoSlot, stream: Weak<PwStream>) {
    let mut converter = Converter::new();
    let mut spare = Vec::new();
    let mut asked = PwBuffers::Memory;
    // The GPU feed told where its refused DMA-BUFs go. Held weakly, so a new
    // feed is never mistaken for one gone at the same address.
    let mut told = Weak::<GpuFeed>::new();
    let mut warned_turned = false;
    while let Some(picture) = pictures.take() {
        let in_memory = picture.memory().is_some();
        // A memory picture comes as the compositor drew it, not turned.
        let size = if in_memory {
            unturned(&picture)
        } else {
            picture.size()
        };
        // Asked on every picture, because the session swaps in a new feed
        // when the size or the codec is changed mid-share.
        let Some((feed, target)) = slot.feed(size) else {
            continue;
        };
        let wanted = buffers_for(&feed);
        if wanted != asked {
            log::info!("capture: asking the compositor for {wanted:?} buffers");
            if let Some(stream) = stream.upgrade() {
                stream.set_buffers(wanted);
            }
            asked = wanted;
        }
        if let Feed::Gpu(gpu) = &feed {
            if !Weak::ptr_eq(&told, &Arc::downgrade(gpu)) {
                let stream = stream.clone();
                gpu.on_import_failed(Box::new(move |drm_format, modifier| {
                    if let Some(stream) = stream.upgrade() {
                        stream.drop_modifier(drm_format, modifier);
                    }
                }));
                told = Arc::downgrade(gpu);
            }
        }
        if let Some((data, stride)) = picture.memory() {
            if picture.transform() != 0 && !warned_turned {
                log::warn!("capture: the screen is turned, and a memory picture is sent as drawn");
                warned_turned = true;
            }
            let rows = whole_rows(data, stride, size.height, &mut spare);
            converter.send(rows, stride, size, feed, target);
            continue;
        }
        match feed {
            Feed::Gpu(gpu) if gpu.takes_dmabuf() => {
                gpu.send(Picture::DmaBuf(picture), target, now_us());
            }
            // The raw path cannot read one: dropped while the switch to
            // memory lands.
            _ => {}
        }
    }
}

/// `data` as `height` whole rows of `stride`, which libyuv's checks ask for.
/// A cropped picture's last row stops at the crop's edge, and the library
/// hands over whole rows only where the buffer has them; the rest is copied
/// into `spare`, padded.
fn whole_rows<'a>(data: &'a [u8], stride: u32, height: u32, spare: &'a mut Vec<u8>) -> &'a [u8] {
    let len = stride as usize * height as usize;
    if data.len() >= len {
        return data;
    }
    spare.clear();
    spare.extend_from_slice(data);
    spare.resize(len, 0);
    spare
}

/// A picture's size before the compositor's turn, which a quarter turn
/// (`SPA_META_TRANSFORMATION_90`, `_270` and their flips: the odd ones)
/// swaps.
fn unturned(picture: &PwPicture) -> Size {
    let size = picture.size();
    if picture.transform() & 1 == 1 {
        Size {
            width: size.height,
            height: size.width,
        }
    } else {
        size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_feed_asks_for_the_buffers_it_can_use() {
        // Raw: libwebrtc reads the picture from memory.
        assert_eq!(wanted_buffers(None), PwBuffers::Memory);
        // VAAPI imports the DMA-BUF.
        assert_eq!(wanted_buffers(Some(true)), PwBuffers::DmaBuf);
        // NVENC takes the picture from memory, for now.
        assert_eq!(wanted_buffers(Some(false)), PwBuffers::Memory);
    }

    #[test]
    fn wayland_is_a_display_and_a_wayland_session() {
        assert!(on_wayland_from(Some("wayland-0"), Some("wayland")));
        assert!(!on_wayland_from(None, Some("wayland")));
        assert!(!on_wayland_from(Some(""), Some("wayland")));
        assert!(!on_wayland_from(Some("wayland-0"), Some("x11")));
        assert!(!on_wayland_from(Some("wayland-0"), None));
    }

    #[test]
    fn a_share_ends_with_its_stream_or_its_portal_session() {
        assert_eq!(ended_by(None, false), None);
        assert_eq!(
            ended_by(Some("unconnected".into()), false).as_deref(),
            Some("unconnected")
        );
        // GNOME closes the session when the shared window closes, and only
        // pauses the stream.
        assert_eq!(ended_by(None, true).as_deref(), Some(SESSION_CLOSED));
        assert_eq!(
            ended_by(Some("unconnected".into()), true).as_deref(),
            Some("unconnected")
        );
    }

    #[test]
    fn a_cropped_picture_reaches_the_converter_in_whole_rows() {
        // Three rows of a 16-byte stride, cropped to 8 bytes wide: the last
        // row stops at the crop's edge, short of the stride.
        let tight: Vec<u8> = (0..40).collect();
        let mut spare = Vec::new();
        let rows = whole_rows(&tight, 16, 3, &mut spare);
        assert_eq!(rows.len(), 48);
        assert_eq!(&rows[..40], &tight[..]);
        // Whole rows already: handed on as they are, not copied.
        let whole = vec![7u8; 48];
        let mut spare = Vec::new();
        assert!(std::ptr::eq(
            whole_rows(&whole, 16, 3, &mut spare),
            &whole[..]
        ));
        assert!(spare.is_empty());
    }
}
