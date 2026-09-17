import 'package:flutter_webrtc/flutter_webrtc.dart';

/// One poll's worth of receive-side numbers for a video track.
///
/// Every field is nullable because a report can arrive before the value it
/// carries exists — rates in particular need two polls before they mean
/// anything, and the overlay simply omits a row it has no number for.
class VideoStreamStats {
  final int? width;
  final int? height;
  final double? fps;
  final double? bitrateKbps;
  final int? packetsLost;
  final double? jitterMs;
  final String? codec;
  final double? rttMs;
  final int? framesDroppedPerSec;

  const VideoStreamStats({
    this.width,
    this.height,
    this.fps,
    this.bitrateKbps,
    this.packetsLost,
    this.jitterMs,
    this.codec,
    this.rttMs,
    this.framesDroppedPerSec,
  });

  /// Resolution is the one value the overlay refuses to render without — a
  /// stats box with no picture size is just noise.
  bool get hasResolution => width != null && height != null;

  String get resolutionLabel => '${width}x$height';

  /// Picture classes the badge names, by the picture's shorter side.
  static const _heightClasses = [
    144,
    240,
    360,
    480,
    540,
    720,
    1080,
    1440,
    2160,
  ];

  /// Frame rates the badge names. Measured rates wander a frame or two each
  /// second; snapping keeps the badge from flickering between 58 and 60.
  static const _rateClasses = [5, 10, 15, 24, 30, 60, 90, 120, 144, 240];

  /// The short "1080p · 60fps" line beside a sharer's name, or null before
  /// the picture size is known. A 1920x1048 window is still "1080p".
  String? get qualityLabel {
    if (!hasResolution) return null;
    final side = width! < height! ? width! : height!;
    final resolution = '${_nearest(_heightClasses, side)}p';
    final rate = fps;
    if (rate == null || rate <= 0) return resolution;
    return '$resolution · ${_nearest(_rateClasses, rate)}fps';
  }

  static int _nearest(List<int> classes, num value) => classes.reduce(
    (best, next) => (next - value).abs() < (best - value).abs() ? next : best,
  );

  /// Kbps below 1 Mbps, Mbps above it.
  String? get bitrateLabel {
    final kbps = bitrateKbps;
    if (kbps == null) return null;
    return kbps >= 1000
        ? '${(kbps / 1000).toStringAsFixed(1)} Mbps'
        : '${kbps.toStringAsFixed(0)} Kbps';
  }
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
