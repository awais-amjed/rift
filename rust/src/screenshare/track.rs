//! Publishing the video track.
use crate::api::screenshare::types::{ScreenShareConfig, VideoCodec};
use livekit::options::{self, TrackPublishOptions, VideoEncoding};
use livekit::prelude::*;
use livekit::track::{LocalTrack, LocalVideoTrack, TrackSource};
use livekit::webrtc::prelude::RtcVideoSource;
use livekit::webrtc::video_source::native::NativeVideoSource;

const BITS_PER_MEGABIT: u64 = 1_000_000;

pub(crate) async fn publish_video_track(
    room: &Room,
    source: NativeVideoSource,
    config: &ScreenShareConfig,
) -> Result<(), String> {
    let track = LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(source));
    let max_bitrate = u64::from(config.bitrate) * BITS_PER_MEGABIT;
    let video_codec = match config.codec {
        VideoCodec::H264 => options::VideoCodec::H264,
        VideoCodec::VP8 => options::VideoCodec::VP8,
        VideoCodec::VP9 => options::VideoCodec::VP9,
    };
    log::info!(
        "track: publishing {:?} at {} bps, {} fps",
        video_codec,
        max_bitrate,
        config.fps
    );

    room.local_participant()
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
                    max_framerate: f64::from(config.fps),
                }),
                ..Default::default()
            },
        )
        .await
        .map_err(|e| format!("Failed to publish video track: {e:?}"))?;
    Ok(())
}
