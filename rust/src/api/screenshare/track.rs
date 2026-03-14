/// Video track publishing
use super::types::ScreenShareConfig;
use livekit::options::{TrackPublishOptions, VideoCodec};
use livekit::prelude::*;
use livekit::track::{LocalTrack, LocalVideoTrack, TrackSource};
use livekit::webrtc::prelude::RtcVideoSource;
use livekit::webrtc::video_source::native::NativeVideoSource;

/// Publish a screen-share video track to the given room.
#[flutter_rust_bridge::frb(ignore)]
pub async fn publish_video_track(
    room: &Room,
    buffer_source: NativeVideoSource,
    config: &ScreenShareConfig,
) -> Result<(), String> {
    let track =
        LocalVideoTrack::create_video_track("screen_share", RtcVideoSource::Native(buffer_source));

    // Convert bitrate from Mbps to bps
    let bitrate_bps = (config.bitrate * 1_000_000) as u64;

    let video_codec = match config.codec.to_uppercase().as_str() {
        "H264" => VideoCodec::H264,
        "VP9" => VideoCodec::VP9,
        _ => VideoCodec::VP8, // default to VP8
    };

    println!(
        "Publishing with codec: {}, bitrate: {} bps ({} Mbps), FPS: {}",
        config.codec, bitrate_bps, config.bitrate, config.fps
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
                video_encoding: Some(livekit::options::VideoEncoding {
                    max_bitrate: bitrate_bps,
                    max_framerate: config.fps as f64,
                }),
                ..Default::default()
            },
        )
        .await
        .map_err(|e| format!("Failed to publish track: {:?}", e))?;

    Ok(())
}
