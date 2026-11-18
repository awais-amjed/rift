//! What WebRTC did with the share's picture, said in the log every few
//! seconds.
//!
//! A friend's whole-screen RDR2 share reached its viewer at 1–18 fps and
//! 0.3–2 Mbps (Nov 18 2026), and the sharer's log could not say whether the
//! pictures were lost before the encoder, in the encoder, or on the way: it
//! had no send statistics at all. This reads WebRTC's own, the ones a
//! browser's `getStats` gives, and says how many frames went out, how many
//! were keyframes and why (a viewer's PLI, a NACK), the estimate WebRTC sends
//! to, and what limits it. People send the log with a bug report, and none of
//! this is secret.

use std::time::Duration;

use livekit::webrtc::stats::{IceCandidatePairState, QualityLimitationReason, RtcStats};

/// How often the report is made.
pub(crate) const REPORT_EVERY: Duration = Duration::from_secs(5);

/// WebRTC's running totals for the share's picture, and the figures that
/// stand for the moment they were read.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct SendTotals {
    pub frames_sent: u32,
    pub frames_encoded: u32,
    pub key_frames: u32,
    pub huge_frames: u32,
    pub bytes_sent: u64,
    pub retransmitted_bytes: u64,
    pub pli: u32,
    pub fir: u32,
    pub nack: u32,
    /// Seconds packets waited in the pacer, summed.
    pub packet_send_delay: f64,
    pub packets_sent: u64,
    pub width: u32,
    pub height: u32,
    /// What the encoder is asked for, bits a second.
    pub target_bps: f64,
    /// WebRTC's estimate of what the connection carries, bits a second; 0
    /// when it did not say.
    pub available_bps: f64,
    pub round_trip_ms: f64,
    /// The share of packets the server reported lost, 0 to 1.
    pub fraction_lost: f64,
    pub limited_by: QualityLimitationReason,
    pub encoder: String,
}

impl SendTotals {
    /// The totals out of a track's statistics, or `None` when they hold no
    /// sent picture yet.
    pub(crate) fn from_stats(stats: &[RtcStats]) -> Option<SendTotals> {
        // A share sends one layer; the busiest is it if ever there are more.
        let outbound = stats
            .iter()
            .filter_map(|stat| match stat {
                RtcStats::OutboundRtp(out) if out.stream.kind == "video" => Some(out),
                _ => None,
            })
            .max_by_key(|out| out.sent.bytes_sent)?;
        let remote = stats.iter().find_map(|stat| match stat {
            RtcStats::RemoteInboundRtp(remote)
                if remote.remote_inbound.local_id == outbound.rtc.id =>
            {
                Some(remote)
            }
            _ => None,
        });
        let pair = stats
            .iter()
            .filter_map(|stat| match stat {
                RtcStats::CandidatePair(pair) => Some(&pair.candidate_pair),
                _ => None,
            })
            .filter(|pair| pair.state == Some(IceCandidatePairState::Succeeded))
            .max_by(|a, b| (a.nominated, a.bytes_sent).cmp(&(b.nominated, b.bytes_sent)));
        let out = &outbound.outbound;
        Some(SendTotals {
            frames_sent: out.frames_sent,
            frames_encoded: out.frames_encoded,
            key_frames: out.key_frames_encoded,
            huge_frames: out.huge_frames_sent,
            bytes_sent: outbound.sent.bytes_sent,
            retransmitted_bytes: out.retransmitted_bytes_sent,
            pli: out.pli_count,
            fir: out.fir_count,
            nack: out.nack_count,
            packet_send_delay: out.total_packet_send_delay,
            packets_sent: outbound.sent.packets_sent,
            width: out.frame_width,
            height: out.frame_height,
            target_bps: out.target_bitrate,
            available_bps: pair.map_or(0.0, |pair| pair.available_outgoing_bitrate),
            round_trip_ms: remote
                .map(|remote| remote.remote_inbound.round_trip_time * 1000.0)
                .or_else(|| pair.map(|pair| pair.current_round_trip_time * 1000.0))
                .unwrap_or(0.0),
            fraction_lost: remote.map_or(0.0, |remote| remote.remote_inbound.fraction_lost),
            limited_by: out.quality_limitation_reason,
            encoder: out.encoder_implementation.clone(),
        })
    }
}

/// The line for the time from `before` (the last report, or `None` for the
/// first) to `now`, `seconds` apart.
pub(crate) fn describe(before: Option<&SendTotals>, now: &SendTotals, seconds: f64) -> String {
    let zero = SendTotals::default();
    // A new track (a codec change, a move to another room) starts its
    // totals again; counting from nothing then is right.
    let before = before
        .filter(|before| {
            before.frames_sent <= now.frames_sent && before.bytes_sent <= now.bytes_sent
        })
        .unwrap_or(&zero);
    let seconds = seconds.max(0.001);
    let frames = now.frames_sent - before.frames_sent;
    let packets = now.packets_sent.saturating_sub(before.packets_sent);
    let pacer_ms = if packets > 0 {
        (now.packet_send_delay - before.packet_send_delay).max(0.0) * 1000.0 / packets as f64
    } else {
        0.0
    };
    let mbps = |bps: f64| bps / 1_000_000.0;
    let available = if now.available_bps > 0.0 {
        format!(", {:.1} available", mbps(now.available_bps))
    } else {
        String::new()
    };
    let encoder = if now.encoder.is_empty() {
        String::new()
    } else {
        format!(" ({})", now.encoder)
    };
    format!(
        "screenshare: sent {frames} frames in {seconds:.1} s ({:.1} fps, {} encoded{encoder}) at \
         {}x{}, {} keyframes, {} huge; {:.2} Mbps of {:.2} target{available}; viewers asked \
         PLI {} FIR {} NACK {}, {} KB resent; pacer {pacer_ms:.1} ms a packet, round trip \
         {:.0} ms, {:.1}% lost; limited by {}",
        f64::from(frames) / seconds,
        now.frames_encoded.saturating_sub(before.frames_encoded),
        now.width,
        now.height,
        now.key_frames.saturating_sub(before.key_frames),
        now.huge_frames.saturating_sub(before.huge_frames),
        mbps((now.bytes_sent - before.bytes_sent) as f64 * 8.0 / seconds),
        mbps(now.target_bps),
        now.pli.saturating_sub(before.pli),
        now.fir.saturating_sub(before.fir),
        now.nack.saturating_sub(before.nack),
        now.retransmitted_bytes
            .saturating_sub(before.retransmitted_bytes)
            / 1000,
        now.round_trip_ms,
        now.fraction_lost * 100.0,
        match now.limited_by {
            QualityLimitationReason::None => "nothing",
            QualityLimitationReason::Cpu => "CPU",
            QualityLimitationReason::Bandwidth => "bandwidth",
            QualityLimitationReason::Other => "other",
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn totals(frames: u32, bytes: u64) -> SendTotals {
        SendTotals {
            frames_sent: frames,
            frames_encoded: frames,
            bytes_sent: bytes,
            width: 1920,
            height: 1080,
            target_bps: 11_000_000.0,
            ..SendTotals::default()
        }
    }

    #[test]
    fn the_line_counts_the_time_since_the_last() {
        let before = SendTotals {
            key_frames: 1,
            pli: 2,
            nack: 10,
            packets_sent: 1000,
            packet_send_delay: 1.0,
            ..totals(300, 7_000_000)
        };
        let now = SendTotals {
            key_frames: 3,
            pli: 4,
            nack: 15,
            retransmitted_bytes: 12_000,
            packets_sent: 2000,
            packet_send_delay: 3.0,
            available_bps: 15_000_000.0,
            round_trip_ms: 39.0,
            fraction_lost: 0.01,
            encoder: "NVENC".to_string(),
            ..totals(600, 13_875_000)
        };
        let line = describe(Some(&before), &now, 5.0);
        assert!(
            line.contains("sent 300 frames in 5.0 s (60.0 fps, 300 encoded (NVENC))"),
            "{line}"
        );
        assert!(line.contains("1920x1080, 2 keyframes"), "{line}");
        assert!(
            line.contains("11.00 Mbps of 11.00 target, 15.0 available"),
            "{line}"
        );
        assert!(line.contains("PLI 2 FIR 0 NACK 5, 12 KB resent"), "{line}");
        assert!(
            line.contains("pacer 2.0 ms a packet, round trip 39 ms, 1.0% lost"),
            "{line}"
        );
        assert!(line.contains("limited by nothing"), "{line}");
    }

    #[test]
    fn a_new_track_counts_from_nothing() {
        let before = totals(900, 20_000_000);
        let now = totals(60, 1_000_000);
        let line = describe(Some(&before), &now, 5.0);
        assert!(line.contains("sent 60 frames"), "{line}");
        assert!(!line.contains("available"), "{line}");
    }

    #[test]
    fn the_first_report_counts_from_nothing() {
        let line = describe(None, &totals(250, 5_000_000), 5.0);
        assert!(
            line.contains("sent 250 frames in 5.0 s (50.0 fps"),
            "{line}"
        );
        assert!(line.contains("8.00 Mbps of 11.00 target"), "{line}");
    }

    #[test]
    fn no_outbound_picture_no_totals() {
        assert_eq!(SendTotals::from_stats(&[]), None);
    }
}
