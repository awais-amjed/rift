//! What a viewer tells the sharer about the share it receives, while it is in
//! trouble.
//!
//! A share is one stream, so a viewer whose link loses packets asks for
//! keyframes that every viewer gets, and the sharer's estimate measures only
//! its own link: in a review of a friend's RDR2 share (Nov 18 2026) the
//! sharer's log could not say whether a viewer's link was the limit. So a
//! viewer says, as the [`RECEIVES`] attribute of its voice connection, what
//! each share its watch connection receives lost and asked for over the last
//! few seconds, but only while that is a lot, and the sharer's log names the
//! viewer (`screenshare::session`). The app publishes it: a watch connection
//! may not set attributes, so that it says nothing in the call. A viewer
//! receiving well says nothing, so a call hears no change at all from it:
//! every attribute change is sent to every client.
//!
//! Only a desktop viewer watching through Rust says it. A phone or a browser
//! watches on the call's own connection.
use std::collections::BTreeMap;
use std::time::Instant;

use livekit::webrtc::stats::RtcStats;
use serde::{Deserialize, Serialize};

/// The attribute: a JSON object from each share's identity to a [`Report`].
pub(crate) const RECEIVES: &str = "receives";

/// Lost packets, as a share of those sent, that put a viewer in trouble.
const LOST_PERCENT: f64 = 2.0;

/// Keyframes asked for in one report that put a viewer in trouble. A viewer
/// starting to watch asks for one.
const KEYFRAMES_ASKED: u32 = 2;

/// A receiver's running totals, as WebRTC keeps them.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Totals {
    pub packets_received: u64,
    pub packets_lost: i64,
    /// PLIs and FIRs sent: keyframes asked for.
    pub keyframes_asked: u32,
    pub bytes_received: u64,
    pub at: Instant,
}

impl Totals {
    /// The picture's inbound stream in one receiver's `stats`.
    pub(crate) fn from_stats(stats: &[RtcStats], at: Instant) -> Option<Totals> {
        stats.iter().find_map(|s| match s {
            RtcStats::InboundRtp(i) if i.stream.kind == "video" => Some(Totals {
                packets_received: i.received.packets_received,
                packets_lost: i.received.packets_lost,
                keyframes_asked: i.inbound.pli_count + i.inbound.fir_count,
                bytes_received: i.inbound.bytes_received,
                at,
            }),
            _ => None,
        })
    }
}

/// One share's last few seconds, as told to its sharer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct Report {
    /// Packets lost, in percent of those sent, to a tenth.
    pub lost: f64,
    /// Keyframes asked for.
    pub keys: u32,
    /// What came, in kbps.
    pub kbps: u32,
    /// Over how many seconds.
    pub secs: u32,
}

impl Report {
    /// What happened from `before` to `now`; None when nothing came or the
    /// totals went back, as after a new subscription.
    pub(crate) fn between(before: &Totals, now: &Totals) -> Option<Report> {
        let received = now.packets_received.checked_sub(before.packets_received)?;
        let lost = (now.packets_lost - before.packets_lost).max(0) as u64;
        let keys = now.keyframes_asked.checked_sub(before.keyframes_asked)?;
        let bytes = now.bytes_received.checked_sub(before.bytes_received)?;
        let secs = now.at.saturating_duration_since(before.at).as_secs_f64();
        if received + lost == 0 || secs < 0.5 {
            return None;
        }
        let lost_percent = lost as f64 * 100.0 / (received + lost) as f64;
        Some(Report {
            lost: (lost_percent * 10.0).round() / 10.0,
            keys,
            kbps: (bytes as f64 * 8.0 / secs / 1000.0).round() as u32,
            secs: secs.round() as u32,
        })
    }

    pub(crate) fn in_trouble(&self) -> bool {
        self.lost >= LOST_PERCENT || self.keys >= KEYFRAMES_ASKED
    }

    /// For the sharer's log.
    pub(crate) fn describe(&self) -> String {
        format!(
            "lost {:.1}% of packets, asked for {} keyframes and received {} kbps in {} s",
            self.lost, self.keys, self.kbps, self.secs
        )
    }
}

/// The attribute's value for the reports of shares in trouble, or None when
/// it would not change from `published`. An empty object once all are well
/// again, and nothing at all before any was in trouble.
pub(crate) fn attribute(
    reports: &BTreeMap<String, Report>,
    published: Option<&str>,
) -> Option<String> {
    let troubled: BTreeMap<&String, &Report> = reports
        .iter()
        .filter(|(_, report)| report.in_trouble())
        .collect();
    if troubled.is_empty() && published.is_none_or(|p| p == "{}") {
        return None;
    }
    let value = serde_json::to_string(&troubled).ok()?;
    (published != Some(value.as_str())).then_some(value)
}

/// What `attributes` says of the share `share`, from a viewer that says so.
pub(crate) fn of(
    attributes: &std::collections::HashMap<String, String>,
    share: &str,
) -> Option<Report> {
    let raw = attributes.get(RECEIVES)?;
    let mut all: BTreeMap<String, Report> = serde_json::from_str(raw).ok()?;
    all.remove(share)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::time::Duration;

    fn totals(received: u64, lost: i64, asked: u32, bytes: u64, at: Instant) -> Totals {
        Totals {
            packets_received: received,
            packets_lost: lost,
            keyframes_asked: asked,
            bytes_received: bytes,
            at,
        }
    }

    #[test]
    fn a_report_is_what_changed_over_the_seconds_between() {
        let start = Instant::now();
        let before = totals(1_000, 10, 1, 1_000_000, start);
        let now = totals(
            5_850,
            160,
            5,
            1_000_000 + 1_250_000 * 5,
            start + Duration::from_secs(5),
        );
        let report = Report::between(&before, &now).unwrap();
        assert_eq!(
            report,
            Report {
                lost: 3.0,
                keys: 4,
                kbps: 10_000,
                secs: 5
            }
        );
        assert!(report.in_trouble());
    }

    #[test]
    fn totals_that_went_back_or_nothing_received_make_no_report() {
        let start = Instant::now();
        let later = start + Duration::from_secs(5);
        let before = totals(1_000, 0, 3, 1_000, start);
        assert_eq!(Report::between(&before, &totals(10, 0, 0, 10, later)), None);
        assert_eq!(
            Report::between(&before, &totals(1_000, 0, 3, 1_000, later)),
            None
        );
    }

    fn report(lost: f64, keys: u32) -> Report {
        Report {
            lost,
            keys,
            kbps: 8_000,
            secs: 5,
        }
    }

    #[test]
    fn a_viewer_receiving_well_says_nothing() {
        let reports = BTreeMap::from([("a~pc_share".to_string(), report(0.5, 1))]);
        assert_eq!(attribute(&reports, None), None);
    }

    #[test]
    fn a_viewer_in_trouble_says_so_until_it_is_well_again() {
        let share = "a~pc_share".to_string();
        let troubled = BTreeMap::from([(share.clone(), report(4.0, 3))]);
        let said = attribute(&troubled, None).unwrap();
        assert_eq!(
            said,
            r#"{"a~pc_share":{"lost":4.0,"keys":3,"kbps":8000,"secs":5}}"#
        );
        // The same again is not sent again.
        assert_eq!(attribute(&troubled, Some(&said)), None);
        // Well again: cleared once.
        let well = BTreeMap::from([(share, report(0.0, 0))]);
        assert_eq!(attribute(&well, Some(&said)).as_deref(), Some("{}"));
        assert_eq!(attribute(&well, Some("{}")), None);
    }

    #[test]
    fn the_sharer_reads_its_own_share_from_the_attribute() {
        let said = attribute(
            &BTreeMap::from([
                ("a~pc_share".to_string(), report(4.0, 3)),
                ("b~pc_share".to_string(), report(0.0, 5)),
            ]),
            None,
        )
        .unwrap();
        let attributes = HashMap::from([(RECEIVES.to_string(), said)]);
        assert_eq!(of(&attributes, "b~pc_share"), Some(report(0.0, 5)));
        assert_eq!(of(&attributes, "c~pc_share"), None);
        let garbled = HashMap::from([(RECEIVES.to_string(), "{".to_string())]);
        assert_eq!(of(&garbled, "a~pc_share"), None);
        assert_eq!(
            report(4.0, 3).describe(),
            "lost 4.0% of packets, asked for 3 keyframes and received 8000 kbps in 5 s"
        );
    }
}
