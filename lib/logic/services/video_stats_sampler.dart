import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'inbound_video.dart';
import 'video_stream_stats.dart';

/// How many keyframes the inbound video stream has decoded, or null before
/// the stream is in [reports] — see `CleanPictureGate`.
int? keyFramesDecodedIn(List<StatsReport> reports) {
  final inbound = reports
      .where((r) => r.type == 'inbound-rtp' && r.values['kind'] == 'video')
      .firstOrNull;
  return (inbound?.values['keyFramesDecoded'] as num?)?.toInt();
}

/// Turns successive polls of a received picture into [VideoStreamStats]:
/// WebRTC stats reports from the call's connection ([sample]), or the Rust
/// watch connection's own counters ([sampleInbound]).
///
/// Stateful on purpose: bitrate, FPS and dropped frames are *rates*, so each
/// sample is a difference against the previous one. One sampler belongs to
/// one track — feeding it two tracks would mix their counters.
class VideoStatsSampler {
  InboundVideo? _previous;

  /// Milliseconds in one unit of a report's timestamp. libwebrtc's own stats
  /// count in microseconds; a browser's `RTCStats.timestamp` is milliseconds,
  /// and read as microseconds it put every rate on the web 1000 times too
  /// high (a 15 fps share read "240fps", the top of the badge's scale).
  final double _msPerTick;

  VideoStatsSampler({bool? millisecondTimestamps})
    : _msPerTick = (millisecondTimestamps ?? kIsWeb) ? 1 : 0.001;

  /// Reads the inbound video stream out of [reports], or null when it isn't
  /// there yet (the track may not be subscribed).
  VideoStreamStats? sample(List<StatsReport> reports) {
    final inbound = _inboundIn(reports);
    return inbound == null ? null : sampleInbound(inbound);
  }

  /// One poll's counters, against the poll before.
  VideoStreamStats sampleInbound(InboundVideo current) {
    final rates = _ratesSince(_previous, current);
    _previous = current;
    return VideoStreamStats(
      width: current.width,
      height: current.height,
      // Fall back to the reported instantaneous FPS until two polls have
      // gone by and the computed rate is available.
      fps: rates.fps ?? current.framesPerSecond,
      bitrateKbps: rates.bitrateKbps,
      framesDroppedPerSec: rates.framesDroppedPerSec,
      lossPercent: rates.lossPercent,
      jitterMs: current.jitterMs,
      codec: current.codec,
      rttMs: current.rttMs,
    );
  }

  InboundVideo? _inboundIn(List<StatsReport> reports) {
    final inbound = reports
        .where((r) => r.type == 'inbound-rtp' && r.values['kind'] == 'video')
        .firstOrNull;
    if (inbound == null) return null;
    final values = inbound.values;
    final jitter = values['jitter'] as num?;
    final codecId = values['codecId'] as String?;
    return InboundVideo(
      timestampMs: inbound.timestamp * _msPerTick,
      width: values['frameWidth'] as int?,
      height: values['frameHeight'] as int?,
      bytesReceived: (values['bytesReceived'] as num?)?.toDouble(),
      packetsReceived: (values['packetsReceived'] as num?)?.toDouble(),
      framesDecoded: (values['framesDecoded'] as num?)?.toDouble(),
      framesDropped: (values['framesDropped'] as num?)?.toInt(),
      framesPerSecond: (values['framesPerSecond'] as num?)?.toDouble(),
      packetsLost: (values['packetsLost'] as num?)?.toInt(),
      jitterMs: jitter == null ? null : jitter * 1000,
      codec: codecId == null
          ? null
          : _codecNames(reports)[codecId]?.replaceFirst('video/', ''),
      rttMs: _roundTripMs(reports),
    );
  }

  /// Round-trip time from the connected candidate pair, in milliseconds.
  static double? _roundTripMs(List<StatsReport> reports) {
    for (final report in reports) {
      if (report.type != 'candidate-pair') continue;
      if (report.values['state'] != 'succeeded') continue;
      final rtt = report.values['currentRoundTripTime'] as num?;
      return rtt == null ? null : rtt * 1000;
    }
    return null;
  }

  /// codec stats id → mime type, so an inbound report's `codecId` resolves
  /// to something displayable.
  static Map<String, String> _codecNames(List<StatsReport> reports) {
    return {
      for (final report in reports)
        if (report.type == 'codec' && report.values['mimeType'] is String)
          report.id: report.values['mimeType'] as String,
    };
  }

  /// The rates two polls' cumulative counters imply; none on the first poll,
  /// nor across a repeated time, and never a negative one.
  static ({
    double? fps,
    double? bitrateKbps,
    int? framesDroppedPerSec,
    double? lossPercent,
  })
  _ratesSince(InboundVideo? previous, InboundVideo current) {
    const none = (
      fps: null,
      bitrateKbps: null,
      framesDroppedPerSec: null,
      lossPercent: null,
    );
    if (previous == null) return none;

    final dtMs = current.timestampMs - previous.timestampMs;
    if (dtMs <= 0) return none;

    double? bitrateKbps;
    final bytes = current.bytesReceived;
    final prevBytes = previous.bytesReceived;
    if (bytes != null && prevBytes != null && bytes > prevBytes) {
      bitrateKbps = ((bytes - prevBytes) * 8) / dtMs;
    }

    double? fps;
    final frames = current.framesDecoded;
    final prevFrames = previous.framesDecoded;
    if (frames != null && prevFrames != null && frames > prevFrames) {
      fps = ((frames - prevFrames) * 1000) / dtMs;
    }

    int? framesDroppedPerSec;
    final dropped = current.framesDropped;
    final prevDropped = previous.framesDropped;
    if (dropped != null && prevDropped != null) {
      final diff = dropped - prevDropped;
      framesDroppedPerSec = diff > 0 ? (diff * 1000 / dtMs).round() : 0;
    }

    return (
      fps: fps,
      bitrateKbps: bitrateKbps,
      framesDroppedPerSec: framesDroppedPerSec,
      lossPercent: _lossPercent(previous, current),
    );
  }

  /// Lost over received-and-lost between two polls. The running count can
  /// fall, as late packets turn up; that reads as none lost, not as less
  /// than none.
  static double? _lossPercent(InboundVideo previous, InboundVideo current) {
    final lost = current.packetsLost;
    final prevLost = previous.packetsLost;
    final received = current.packetsReceived;
    final prevReceived = previous.packetsReceived;
    if (lost == null ||
        prevLost == null ||
        received == null ||
        prevReceived == null) {
      return null;
    }
    final newlyLost = (lost - prevLost).clamp(0, double.infinity);
    final newlyReceived = (received - prevReceived).clamp(0, double.infinity);
    final sent = newlyLost + newlyReceived;
    if (sent == 0) return null;
    return newlyLost * 100 / sent;
  }
}
