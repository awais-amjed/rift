//! A watched share's picture decoded on the GPU, by Rift's FFmpeg library,
//! instead of by libwebrtc on the CPU.
//!
//! The process's LiveKit runtime is chosen once, at start ([`choose`]): where
//! a GPU decoder is there, it decodes nothing (pass-through, `RIFT.md` in the
//! LiveKit fork), and each watched share's picture is read still encoded, on a
//! thread of its own ([`feed`]), decoded on the GPU the screen is drawn with,
//! and handed to the runner as DMA-BUFs. Nothing comes to the CPU. The
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

#[cfg(not(target_os = "linux"))]
mod elsewhere;
#[cfg(target_os = "linux")]
mod linux;

#[cfg(not(target_os = "linux"))]
use elsewhere::{device, DecodeError, Decoder};
#[cfg(target_os = "linux")]
use linux::{device, DecodeError, Decoder};

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

static GPU: OnceLock<Option<String>> = OnceLock::new();

/// Decides, once and before any room, whether watched shares decode on the
/// GPU. `RIFT_WATCH_DECODE=cpu` keeps libwebrtc's decoder, to compare.
pub(crate) fn choose() {
    GPU.get_or_init(|| {
        let node = if std::env::var("RIFT_WATCH_DECODE").as_deref() == Ok("cpu") {
            Err("RIFT_WATCH_DECODE=cpu".to_string())
        } else {
            device()
        };
        let node = match node {
            Ok(node) => node,
            Err(why) => {
                log::info!("watching: shares decode on the CPU ({why})");
                return None;
            }
        };
        match livekit::webrtc::set_video_decoder_backend(VideoDecoderBackend::PassThrough) {
            Ok(()) => {
                log::info!("watching: shares decode on the GPU ({node})");
                Some(node)
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
pub(crate) fn gpu() -> Option<&'static str> {
    GPU.get()?.as_deref()
}

/// A share's picture being decoded. Dropped, it stops: the thread ends at
/// its next frame or wait.
pub(crate) struct Feed {
    _stop: oneshot::Sender<()>,
}

/// Decodes `track` on `device` into `texture`, on a thread of its own.
/// Called inside the runtime, whose handle the thread reads the track with.
pub(crate) fn feed(
    track: RemoteVideoTrack,
    texture: u64,
    identity: String,
    device: &'static str,
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
            decode(next, texture, &identity, device);
        })
        .map_err(|e| log::warn!("watching: no thread to decode on: {e}"))
        .ok()?;
    Some(Feed { _stop: stop })
}

fn decode(
    mut next: impl FnMut() -> Option<ReceivedEncodedFrame>,
    texture: u64,
    identity: &str,
    device: &str,
) {
    let mut chain = Chain::default();
    let mut decoder: Option<Decoder> = None;
    let mut size = (0, 0);
    let mut asked: Option<Instant> = None;
    while let Some(frame) = next() {
        let Some(codec) = Codec::of(frame.codec) else {
            give_up(
                identity,
                &format!("{:?} is not decoded on the GPU", frame.codec),
            );
            return;
        };
        let key = frame.frame_type == EncodedFrameType::Key;
        match chain.next(codec, key) {
            Next::Wait => {
                log::debug!("watching: {codec:?} frame before a keyframe, skipped");
                ask_for_keyframe(&frame, &mut asked);
                continue;
            }
            Next::Open => match Decoder::open(codec, device) {
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
                if !chain.failed(key) {
                    give_up(
                        identity,
                        &format!("{codec:?} keyframes did not decode ({err})"),
                    );
                    return;
                }
                log::warn!("watching: a picture did not decode ({err}), waiting for a keyframe");
                ask_for_keyframe(&frame, &mut asked);
            }
        }
    }
}

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
/// opened for, and whether a picture failed since the last keyframe, after
/// which only a keyframe decodes cleanly.
#[derive(Default)]
struct Chain {
    codec: Option<Codec>,
    broken: bool,
    failed_keyframes: u32,
}

impl Chain {
    fn next(&mut self, codec: Codec, key: bool) -> Next {
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
    /// no later keyframe would fix.
    fn failed(&mut self, key: bool) -> bool {
        self.broken = true;
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
        assert_eq!(chain.next(Codec::H264, false), Next::Wait);
        assert_eq!(chain.next(Codec::H264, true), Next::Open);
        assert_eq!(chain.next(Codec::H264, false), Next::Decode);
    }

    #[test]
    fn a_failed_picture_waits_for_the_next_keyframe() {
        let mut chain = Chain::default();
        chain.next(Codec::Vp9, true);
        assert!(chain.failed(false));
        assert_eq!(chain.next(Codec::Vp9, false), Next::Wait);
        assert_eq!(chain.next(Codec::Vp9, true), Next::Decode);
        chain.decoded(true);
        assert_eq!(chain.next(Codec::Vp9, false), Next::Decode);
    }

    #[test]
    fn keyframes_that_keep_failing_give_up() {
        let mut chain = Chain::default();
        chain.next(Codec::H264, true);
        assert!(chain.failed(true));
        assert!(chain.failed(true));
        assert!(!chain.failed(true));
    }

    #[test]
    fn a_keyframe_that_decodes_forgives_the_ones_before() {
        let mut chain = Chain::default();
        chain.next(Codec::H264, true);
        assert!(chain.failed(true));
        assert!(chain.failed(true));
        chain.decoded(true);
        assert!(chain.failed(true));
        assert!(chain.failed(true));
    }

    #[test]
    fn a_new_codec_opens_a_new_decoder_at_its_keyframe() {
        let mut chain = Chain::default();
        chain.next(Codec::Vp9, true);
        assert!(chain.failed(false));
        assert_eq!(chain.next(Codec::H264, false), Next::Wait);
        assert_eq!(chain.next(Codec::H264, true), Next::Open);
        assert_eq!(chain.next(Codec::H264, false), Next::Decode);
    }
}
