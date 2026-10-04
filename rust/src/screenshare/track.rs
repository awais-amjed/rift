//! Publishing the video track.
use crate::api::screenshare::types::{ScreenShareConfig, VideoCodec};
use livekit::options::{self, TrackPublishOptions, VideoEncoding};
use livekit::prelude::*;
use livekit::track::{LocalTrack, LocalVideoTrack, TrackSource};
use livekit::webrtc::prelude::RtcVideoSource;
use livekit::webrtc::video_source::native::NativeVideoSource;

const BITS_PER_MEGABIT: u64 = 1_000_000;

/// What the published picture is held to, out of the share's settings.
/// Copied rather than borrowed, because a share waiting on a minimised window
/// publishes long after the call that started it has returned.
#[derive(Clone, Copy)]
pub(crate) struct TrackSettings {
    /// Height cap in rows.
    pub max_height: u32,
    pub fps: u32,
    /// Megabits per second.
    pub bitrate: u32,
    pub codec: VideoCodec,
}

impl From<&ScreenShareConfig> for TrackSettings {
    fn from(config: &ScreenShareConfig) -> Self {
        Self {
            max_height: config.resolution,
            fps: config.fps,
            bitrate: config.bitrate,
            codec: config.codec,
        }
    }
}

pub(crate) async fn publish_video_track(
    participant: &LocalParticipant,
    source: NativeVideoSource,
    settings: &TrackSettings,
) -> Result<(), String> {
    let track = LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
    let max_bitrate = u64::from(settings.bitrate) * BITS_PER_MEGABIT;
    let video_codec = match settings.codec {
        VideoCodec::H264 => options::VideoCodec::H264,
        VideoCodec::VP8 => options::VideoCodec::VP8,
        VideoCodec::VP9 => options::VideoCodec::VP9,
    };
    log::info!(
        "track: publishing {:?} at {} bps, {} fps",
        video_codec,
        max_bitrate,
        settings.fps
    );

    participant
        .publish_track(
            LocalTrack::Video(track),
            TrackPublishOptions {
                source: TrackSource::Screenshare,
                video_codec,
                simulcast: false,
                dtx: false,
                red: false,
                preconnect_buffer: true,
                video_encoding: Some(VideoEncoding {
                    max_bitrate,
                    max_framerate: f64::from(settings.fps),
                }),
                ..Default::default()
            },
        )
        .await
        .map_err(|e| format!("Failed to publish video track: {e:?}"))?;
    Ok(())
}
