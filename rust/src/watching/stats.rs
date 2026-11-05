//! A watched share's receive numbers, read from libwebrtc's own stats for its
//! picture on the watch connection: what the call's stats card shows for a
//! share the call receives (`VideoStatsSampler` in the app), for one Rust does.
//!
//! The counters go to the app as they are, cumulative, and it turns two polls
//! into rates, as it does for the call's. Decoded on the GPU they still count:
//! the pass-through decoder hands libwebrtc a picture of the right size for
//! each frame it is given, so frames decoded and the picture's size are the
//! frames that reached Rift's decoder.
use crate::api::watching::WatchStats;
use livekit::webrtc::stats::{IceCandidatePairState, RtcStats};

/// The picture's inbound stream in `stats` — one receiver's report — with its
/// codec's name and the connection's round trip, or None before it is there.
pub(crate) fn received(stats: &[RtcStats]) -> Option<WatchStats> {
    let inbound = stats.iter().find_map(|s| match s {
        RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(i),
        _ => None,
    })?;
    let codec = stats
        .iter()
        .find_map(|s| match s {
            RtcStats::Codec(c) if c.rtc.id == inbound.stream.codec_id => {
                Some(c.codec.mime_type.trim_start_matches("video/").to_string())
            }
            _ => None,
        })
        .unwrap_or_default();
    let rtt_ms = stats.iter().find_map(|s| match s {
        RtcStats::CandidatePair(p)
            if p.candidate_pair.state == Some(IceCandidatePairState::Succeeded) =>
        {
            Some(p.candidate_pair.current_round_trip_time * 1000.0)
        }
        _ => None,
    });
    Some(WatchStats {
        timestamp_us: inbound.rtc.timestamp,
        width: inbound.inbound.frame_width,
        height: inbound.inbound.frame_height,
        frames_decoded: inbound.inbound.frames_decoded,
        frames_dropped: inbound.inbound.frames_dropped,
        frames_per_second: inbound.inbound.frames_per_second,
        bytes_received: inbound.inbound.bytes_received,
        packets_received: inbound.received.packets_received,
        packets_lost: inbound.received.packets_lost,
        jitter_ms: inbound.received.jitter * 1000.0,
        codec,
        rtt_ms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use livekit::webrtc::stats::{CandidatePairStats, CodecStats, InboundRtpStats};

    fn inbound(kind: &str, codec_id: &str) -> RtcStats {
        let mut i = InboundRtpStats::default();
        i.rtc.timestamp = 5_000_000;
        i.stream.kind = kind.to_string();
        i.stream.codec_id = codec_id.to_string();
        i.inbound.frame_width = 1920;
        i.inbound.frame_height = 1080;
        i.inbound.frames_decoded = 600;
        i.inbound.bytes_received = 4_000_000;
        i.received.jitter = 0.004;
        i.received.packets_received = 900;
        i.received.packets_lost = 3;
        RtcStats::InboundRtp(i)
    }

    fn codec(id: &str, mime: &str) -> RtcStats {
        let mut c = CodecStats::default();
        c.rtc.id = id.to_string();
        c.codec.mime_type = mime.to_string();
        RtcStats::Codec(c)
    }

    fn pair(state: IceCandidatePairState, rtt_s: f64) -> RtcStats {
        let mut p = CandidatePairStats::default();
        p.candidate_pair.state = Some(state);
        p.candidate_pair.current_round_trip_time = rtt_s;
        RtcStats::CandidatePair(p)
    }

    #[test]
    fn nothing_before_the_picture_arrives() {
        assert!(received(&[]).is_none());
        assert!(received(&[inbound("audio", "c1")]).is_none());
    }

    #[test]
    fn reads_the_pictures_counters_its_codec_and_the_round_trip() {
        let stats = received(&[
            pair(IceCandidatePairState::InProgress, 0.5),
            codec("c0", "video/VP8"),
            inbound("video", "c1"),
            codec("c1", "video/VP9"),
            pair(IceCandidatePairState::Succeeded, 0.012),
        ])
        .expect("an inbound picture");
        assert_eq!(stats.timestamp_us, 5_000_000);
        assert_eq!((stats.width, stats.height), (1920, 1080));
        assert_eq!(stats.frames_decoded, 600);
        assert_eq!(stats.bytes_received, 4_000_000);
        assert_eq!((stats.packets_received, stats.packets_lost), (900, 3));
        assert_eq!(stats.codec, "VP9");
        assert!((stats.jitter_ms - 4.0).abs() < 1e-9);
        let rtt = stats.rtt_ms.expect("the connected pair's round trip");
        assert!((rtt - 12.0).abs() < 1e-9);
    }

    #[test]
    fn no_round_trip_without_a_connected_pair() {
        let stats = received(&[inbound("video", "c1")]).expect("an inbound picture");
        assert_eq!(stats.rtt_ms, None);
        assert_eq!(stats.codec, "");
    }
}
