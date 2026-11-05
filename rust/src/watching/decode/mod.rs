//! A watched share's picture decoded on the GPU, by Rift's FFmpeg library,
//! instead of by libwebrtc on the CPU.
//!
//! The process's LiveKit runtime is chosen once, at start ([`choose`]): where
//! a GPU decoder is there, it decodes nothing (pass-through, `RIFT.md` in the
//! LiveKit fork), and each watched share's picture is read still encoded, on a
//! thread of its own ([`feed`]), decoded on the GPU the screen is drawn with,
//! and handed to the runner: on Linux as DMA-BUFs from Intel or AMD, and from
//! NVIDIA as CUDA's memory, which the runner has copied into its GL textures
//! on the GPU; on Windows as a slice of the decoder's D3D11 textures, decoded
//! on the runner's own device. Nothing comes to the CPU. The
//! runtime cannot change while a room holds it, so the choice is the
//! process's: the share connections only send, and never notice.
//!
//! Where there is none, libwebrtc decodes as before (`session::show`). A
//! share the GPU cannot decode ends the watch connection for the call, and
//! the app watches through the call's own connection, as for any other
//! failure.
use super::frames;
use super::session;
use futures_util::StreamExt;
use livekit::prelude::RemoteVideoTrack;
use livekit::webrtc::peer_connection_factory::VideoDecoderBackend;
use livekit::webrtc::video_frame::{EncodedFrameType, EncodedVideoCodec};
use livekit::webrtc::video_stream::native::{
    NativeEncodedVideoStream, NativeEncodedVideoStreamOptions, ReceivedEncodedFrame,
};
use std::sync::OnceLock;
use std::thread;
use std::time::{Duration, Instant};
use tokio::sync::oneshot;

#[cfg(not(any(target_os = "linux", windows)))]
mod elsewhere;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(windows)]
mod windows;

#[cfg(not(any(target_os = "linux", windows)))]
pub(crate) use elsewhere::Gpu;
#[cfg(not(any(target_os = "linux", windows)))]
use elsewhere::{device, DecodeError, Decoder};
#[cfg(target_os = "linux")]
pub(crate) use linux::Gpu;
#[cfg(target_os = "linux")]
use linux::{device, DecodeError, Decoder};
#[cfg(all(test, windows))]
pub(crate) use windows::tests::{slice_holds, RunnerDeviceInPlace};
#[cfg(windows)]
pub(crate) use windows::Gpu;
#[cfg(windows)]
use windows::{device, DecodeError, Decoder};

/// How far the decoder may fall behind before the stream flushes what waits
/// and asks for a keyframe: half a second at 60 pictures a second. Only a
/// stalled GPU gets there.
const PENDING_FRAMES: usize = 30;

/// Keyframes in a row that may fail to decode before the GPU is given up on.
const KEYFRAMES_TRIED: u32 = 3;

/// How often a keyframe is asked for while waiting for one.
const ASK_EVERY: Duration = Duration::from_secs(1);

/// The codecs a share arrives in that the GPU decodes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Codec {
    H264,
    Vp8,
    Vp9,
}

impl Codec {
    fn of(codec: EncodedVideoCodec) -> Option<Codec> {
        match codec {
            EncodedVideoCodec::H264 => Some(Codec::H264),
            EncodedVideoCodec::VP8 => Some(Codec::Vp8),
            EncodedVideoCodec::VP9 => Some(Codec::Vp9),
            _ => None,
        }
    }
}

static GPU: OnceLock<Option<Gpu>> = OnceLock::new();

/// Decides, once and before any room, whether watched shares decode on the
/// GPU. `RIFT_WATCH_DECODE=cpu` keeps libwebrtc's decoder, to compare.
pub(crate) fn choose() {
    GPU.get_or_init(|| {
        let gpu = if std::env::var("RIFT_WATCH_DECODE").as_deref() == Ok("cpu") {
            Err("RIFT_WATCH_DECODE=cpu".to_string())
        } else {
            device()
        };
        let gpu = match gpu {
            Ok(gpu) => gpu,
            Err(why) => {
                log::info!("watching: shares decode on the CPU ({why})");
                return None;
            }
        };
        match livekit::webrtc::set_video_decoder_backend(VideoDecoderBackend::PassThrough) {
            Ok(()) => {
                log::info!("watching: shares decode on the GPU ({gpu})");
                Some(gpu)
            }
            Err(e) => {
                log::warn!("watching: shares decode on the CPU ({e})");
                None
            }
        }
    });
}

/// The GPU watched shares decode on, when they do: the runtime then decodes
/// nothing itself.
pub(crate) fn gpu() -> Option<&'static Gpu> {
    GPU.get()?.as_ref()
}

/// A share's picture being decoded. Dropped, it stops: the thread ends at
/// its next frame or wait.
pub(crate) struct Feed {
    _stop: oneshot::Sender<()>,
}

/// Decodes `track` on `gpu` into `texture`, on a thread of its own.
/// Called inside the runtime, whose handle the thread reads the track with.
pub(crate) fn feed(
    track: RemoteVideoTrack,
    texture: u64,
    identity: String,
    gpu: &'static Gpu,
) -> Option<Feed> {
    let (stop, stopped) = oneshot::channel();
    let runtime = tokio::runtime::Handle::current();
    let mut options = NativeEncodedVideoStreamOptions::default();
    options.max_pending_frames = Some(PENDING_FRAMES);
    let stream = NativeEncodedVideoStream::new(track.rtc_track(), options);
    thread::Builder::new()
        .name("rift-watch-decode".to_string())
        .spawn(move || {
            // Read here, not on the runtime: a decoder slower than the share
            // leaves frames waiting in the stream, which flushes them whole
            // and asks for a keyframe, rather than losing single frames
            // later ones depend on.
            let mut stream = stream;
            let mut stopped = stopped;
            let next = || {
                runtime.block_on(async {
                    tokio::select! {
                        frame = stream.next() => frame,
                        _ = &mut stopped => None,
                    }
                })
            };
            decode(next, texture, &identity, gpu);
        })
        .map_err(|e| log::warn!("watching: no thread to decode on: {e}"))
        .ok()?;
    Some(Feed { _stop: stop })
}

fn decode(
    mut next: impl FnMut() -> Option<ReceivedEncodedFrame>,
    texture: u64,
    identity: &str,
    gpu: &Gpu,
) {
    let mut chain = Chain::default();
    let mut decoder: Option<Decoder> = None;
    let mut size = (0, 0);
    let mut asked: Option<Instant> = None;
    let mut received: u32 = 0;
    while let Some(frame) = next() {
        received = received.saturating_add(1);
        stall_for_test(received);
        let Some(codec) = Codec::of(frame.codec) else {
            give_up(
                identity,
                &format!("{:?} is not decoded on the GPU", frame.codec),
            );
            return;
        };
        let key = frame.frame_type == EncodedFrameType::Key;
        if frame.after_gap && !key && !chain.broken {
            log::info!("watching: {codec:?} frames were lost, waiting for a keyframe");
        }
        match chain.next(codec, key, frame.after_gap) {
            Next::Wait => {
                log::debug!("watching: {codec:?} frame before a keyframe, skipped");
                ask_for_keyframe(&frame, &mut asked);
                continue;
            }
            Next::Open => match Decoder::open(codec, gpu) {
                Ok(opened) => {
                    log::info!("watching: decoding {codec:?} on {}", opened.driver());
                    decoder = Some(opened);
                }
                Err(why) => {
                    give_up(identity, &why);
                    return;
                }
            },
            Next::Decode => {}
        }
        let Some(decoder) = decoder.as_mut() else {
            continue;
        };
        match decoder.decode(frame.payload(), frame.timestamp_us) {
            Ok(pictures) => {
                chain.decoded(key);
                for picture in pictures {
                    session::picture_size(identity, &mut size, picture.size());
                    if !frames::deliver(texture, picture) {
                        return;
                    }
                }
            }
            Err(DecodeError::NoGpuDecoder) => {
                give_up(identity, &format!("the GPU cannot decode this {codec:?}"));
                return;
            }
            Err(DecodeError::Failed(err)) => {
                let lost = decoder.device_lost();
                if !chain.failed(key, lost) {
                    let why = if lost {
                        format!("the GPU device was lost ({err})")
                    } else {
                        format!("{codec:?} keyframes did not decode ({err})")
                    };
                    give_up(identity, &why);
                    return;
                }
                log::warn!("watching: a picture did not decode ({err}), waiting for a keyframe");
                ask_for_keyframe(&frame, &mut asked);
            }
        }
    }
}

/// Debug builds only: `RIFT_WATCH_DECODE_STALL_AT=<n>` stops the decoder for
/// two seconds at its n-th frame, as a stalled GPU would, so the stream
/// flushing its backlog can be seen in the app.
#[cfg(debug_assertions)]
fn stall_for_test(received: u32) {
    static AT: OnceLock<Option<u32>> = OnceLock::new();
    let at = AT.get_or_init(|| {
        std::env::var("RIFT_WATCH_DECODE_STALL_AT")
            .ok()?
            .parse()
            .ok()
    });
    if *at == Some(received) {
        log::info!("watching: stalling the decoder for 2 s (RIFT_WATCH_DECODE_STALL_AT)");
        thread::sleep(Duration::from_secs(2));
    }
}

#[cfg(not(debug_assertions))]
fn stall_for_test(_received: u32) {}

fn ask_for_keyframe(frame: &ReceivedEncodedFrame, asked: &mut Option<Instant>) {
    if asked.is_none_or(|at| at.elapsed() >= ASK_EVERY) {
        frame.request_keyframe();
        *asked = Some(Instant::now());
    }
}

/// The GPU cannot show this share: the app watches the call's way instead.
fn give_up(identity: &str, why: &str) {
    log::warn!("watching: not decoding on the GPU: {why}");
    session::lost(&format!("decoding {identity} on the GPU failed: {why}"));
}

/// What to do with a received frame.
#[derive(Debug, PartialEq, Eq)]
enum Next {
    /// Skip it: the decoder needs a keyframe first.
    Wait,
    /// Open a decoder for its codec, then decode it.
    Open,
    Decode,
}

/// Where the stream's reference chain stands: which codec the decoder was
/// opened for, and whether a picture failed or frames were lost since the
/// last keyframe, after which only a keyframe decodes cleanly. Decoded
/// against references thrown away, the picture smears until one comes.
#[derive(Default)]
struct Chain {
    codec: Option<Codec>,
    broken: bool,
    failed_keyframes: u32,
}

impl Chain {
    /// [after_gap]: the stream lost frames this one may build on, a flushed
    /// backlog above all, and no keyframe has come since.
    fn next(&mut self, codec: Codec, key: bool, after_gap: bool) -> Next {
        if after_gap && !key {
            self.broken = true;
        }
        if self.codec != Some(codec) {
            if !key {
                return Next::Wait;
            }
            *self = Chain {
                codec: Some(codec),
                ..Chain::default()
            };
            return Next::Open;
        }
        if self.broken && !key {
            return Next::Wait;
        }
        Next::Decode
    }

    fn decoded(&mut self, key: bool) {
        if key {
            self.broken = false;
            self.failed_keyframes = 0;
        }
    }

    /// A picture did not decode. False once keyframes keep failing, which
    /// no later keyframe would fix, and at once when the device it decodes
    /// on was removed.
    fn failed(&mut self, key: bool, device_lost: bool) -> bool {
        self.broken = true;
        if device_lost {
            return false;
        }
        if key {
            self.failed_keyframes += 1;
        }
        self.failed_keyframes < KEYFRAMES_TRIED
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stream_joined_mid_way_waits_for_a_keyframe() {
        let mut chain = Chain::default();
        assert_eq!(chain.next(Codec::H264, false, false), Next::Wait);
        assert_eq!(chain.next(Codec::H264, true, false), Next::Open);
        assert_eq!(chain.next(Codec::H264, false, false), Next::Decode);
    }

    #[test]
    fn a_failed_picture_waits_for_the_next_keyframe() {
        let mut chain = Chain::default();
        chain.next(Codec::Vp9, true, false);
        assert!(chain.failed(false, false));
        assert_eq!(chain.next(Codec::Vp9, false, false), Next::Wait);
        assert_eq!(chain.next(Codec::Vp9, true, false), Next::Decode);
        chain.decoded(true);
        assert_eq!(chain.next(Codec::Vp9, false, false), Next::Decode);
    }

    #[test]
    fn a_flushed_backlog_waits_for_the_next_keyframe() {
        // A decoder 30 frames behind loses the backlog; the frames after it
        // reference ones it never saw, and the stream marks them.
        let mut chain = Chain::default();
        chain.next(Codec::H264, true, false);
        chain.decoded(true);
        assert_eq!(chain.next(Codec::H264, false, false), Next::Decode);
        assert_eq!(chain.next(Codec::H264, false, true), Next::Wait);
        assert_eq!(
            chain.next(Codec::H264, false, false),
            Next::Wait,
            "still nothing to build on until a keyframe"
        );
        assert_eq!(chain.next(Codec::H264, true, true), Next::Decode);
        chain.decoded(true);
        assert_eq!(chain.next(Codec::H264, false, false), Next::Decode);
    }

    #[test]
    fn keyframes_that_keep_failing_give_up() {
        let mut chain = Chain::default();
        chain.next(Codec::H264, true, false);
        assert!(chain.failed(true, false));
        assert!(chain.failed(true, false));
        assert!(!chain.failed(true, false));
    }

    #[test]
    fn a_lost_device_gives_up_at_the_first_failure() {
        // No keyframe decodes on a removed device; waiting for three only
        // kept the share blank for seconds before the call took it.
        let mut chain = Chain::default();
        chain.next(Codec::H264, true, false);
        chain.decoded(true);
        assert!(!chain.failed(false, true));
        let mut chain = Chain::default();
        chain.next(Codec::Vp9, true, false);
        assert!(!chain.failed(true, true));
    }

    #[test]
    fn a_keyframe_that_decodes_forgives_the_ones_before() {
        let mut chain = Chain::default();
        chain.next(Codec::H264, true, false);
        assert!(chain.failed(true, false));
        assert!(chain.failed(true, false));
        chain.decoded(true);
        assert!(chain.failed(true, false));
        assert!(chain.failed(true, false));
    }

    #[test]
    fn a_new_codec_opens_a_new_decoder_at_its_keyframe() {
        let mut chain = Chain::default();
        chain.next(Codec::Vp9, true, false);
        assert!(chain.failed(false, false));
        assert_eq!(chain.next(Codec::H264, false, false), Next::Wait);
        assert_eq!(chain.next(Codec::H264, true, false), Next::Open);
        assert_eq!(chain.next(Codec::H264, false, false), Next::Decode);
    }
}
