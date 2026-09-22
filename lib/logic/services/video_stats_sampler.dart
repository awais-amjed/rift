import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'video_stream_stats.dart';

/// How many keyframes the inbound video stream has decoded, or null before
/// the stream is in [reports] — see `CleanPictureGate`.
int? keyFramesDecodedIn(List<StatsReport> reports) {
  final inbound = reports
      .where((r) => r.type == 'inbound-rtp' && r.values['kind'] == 'video')
      .firstOrNull;
  return (inbound?.values['keyFramesDecoded'] as num?)?.toInt();
}

/// Turns successive WebRTC stats reports into [VideoStreamStats].
///
/// Stateful on purpose: bitrate, FPS and dropped frames are *rates*, so each
/// sample is a difference against the previous one. One sampler belongs to
/// one track — feeding it two tracks would mix their counters.
class VideoStatsSampler {
  _Counters? _previous;

  /// Reads the inbound video stream out of [reports], or null when it isn't
  /// there yet (the track may not be subscribed).
  VideoStreamStats? sample(List<StatsReport> reports) {
    final inbound = reports
        .where((r) => r.type == 'inbound-rtp' && r.values['kind'] == 'video')
        .firstOrNull;
    if (inbound == null) return null;

    final values = inbound.values;
    final current = _Counters(
      timestamp: inbound.timestamp,
      bytesReceived: (values['bytesReceived'] as num?)?.toDouble(),
      framesDecoded: (values['framesDecoded'] as num?)?.toDouble(),
      framesDropped: (values['framesDropped'] as num?)?.toInt(),
    );
    final rates = current.since(_previous);
    _previous = current;

    final jitter = values['jitter'] as num?;
    final codecId = values['codecId'] as String?;

    return VideoStreamStats(
      width: values['frameWidth'] as int?,
      height: values['frameHeight'] as int?,
      // Fall back to the reported instantaneous FPS until two polls have
      // gone by and the computed rate is available.
      fps: rates.fps ?? (values['framesPerSecond'] as num?)?.toDouble(),
      bitrateKbps: rates.bitrateKbps,
      framesDroppedPerSec: rates.framesDroppedPerSec,
      packetsLost: values['packetsLost'] as int?,
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
}

/// The raw cumulative counters one poll reports, and the rates they imply.
class _Counters {
  final double timestamp;
  final double? bytesReceived;
  final double? framesDecoded;
  final int? framesDropped;

  const _Counters({
    required this.timestamp,
    required this.bytesReceived,
    required this.framesDecoded,
    required this.framesDropped,
  });

  ({double? fps, double? bitrateKbps, int? framesDroppedPerSec}) since(
    _Counters? previous,
  ) {
    const none = (fps: null, bitrateKbps: null, framesDroppedPerSec: null);
    if (previous == null) return none;

    // Report timestamps are microseconds.
    final dtMs = (timestamp - previous.timestamp) / 1000;
    if (dtMs <= 0) return none;

    double? bitrateKbps;
    final bytes = bytesReceived;
    final prevBytes = previous.bytesReceived;
    if (bytes != null && prevBytes != null && bytes > prevBytes) {
      bitrateKbps = ((bytes - prevBytes) * 8) / dtMs;
    }

    double? fps;
    final frames = framesDecoded;
    final prevFrames = previous.framesDecoded;
    if (frames != null && prevFrames != null && frames > prevFrames) {
      fps = ((frames - prevFrames) * 1000) / dtMs;
    }

    int? framesDroppedPerSec;
    final dropped = framesDropped;
    final prevDropped = previous.framesDropped;
    if (dropped != null && prevDropped != null) {
      final diff = dropped - prevDropped;
      framesDroppedPerSec = diff > 0 ? diff : 0;
    }

    return (
      fps: fps,
      bitrateKbps: bitrateKbps,
      framesDroppedPerSec: framesDroppedPerSec,
    );
  }
}
