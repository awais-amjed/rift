//! Publishing the video track.
use crate::api::screenshare::types::{ScreenShareConfig, SharePriority, VideoCodec};
use livekit::options::{self, TrackPublishOptions, VideoEncoderBackend, VideoEncoding};
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
    pub priority: SharePriority,
}

impl From<&ScreenShareConfig> for TrackSettings {
    fn from(config: &ScreenShareConfig) -> Self {
        Self {
            max_height: config.resolution,
            fps: config.fps,
            bitrate: config.bitrate,
            codec: config.codec,
            priority: config.priority,
        }
    }
}

/// Publish `source` as the share's picture. A `pre_encoded` source carries
/// H264 the GPU already made, which WebRTC passes through as it is; it cannot
/// scale or drop frames for the connection the way it does with raw ones, so
/// whatever the priority, the encoder keeps the frame rate and lowers its
/// bitrate to what WebRTC asks.
pub(crate) async fn publish_video_track(
    participant: &LocalParticipant,
    source: NativeVideoSource,
    settings: &TrackSettings,
    pre_encoded: bool,
) -> Result<TrackSid, String> {
    let track = LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
    let max_bitrate = u64::from(settings.bitrate) * BITS_PER_MEGABIT;
    let video_codec = match settings.codec {
        VideoCodec::H264 => options::VideoCodec::H264,
        VideoCodec::VP8 => options::VideoCodec::VP8,
        VideoCodec::VP9 => options::VideoCodec::VP9,
    };
    let degradation_preference = match settings.priority {
        SharePriority::Smoothness => options::DegradationPreference::MaintainFramerate,
        SharePriority::Balanced => options::DegradationPreference::Balanced,
        SharePriority::Sharpness => options::DegradationPreference::MaintainResolution,
    };
    log::info!(
        "track: publishing {:?}{} at {} bps, {} fps, keeping {:?}",
        video_codec,
        if pre_encoded { " from the GPU" } else { "" },
        max_bitrate,
        settings.fps,
        settings.priority
    );

    let publication = participant
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
                degradation_preference: Some(degradation_preference),
                video_encoder: if pre_encoded {
                    VideoEncoderBackend::PreEncoded
                } else {
                    VideoEncoderBackend::Auto
                },
                ..Default::default()
            },
        )
        .await
        .map_err(|e| format!("Failed to publish video track: {e:?}"))?;
    Ok(publication.sid())
}
