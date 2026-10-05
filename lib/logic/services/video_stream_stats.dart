import 'dart:math';

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

  /// Picture classes the badge names, each the height of a 16:9 picture.
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
  ///
  /// Named by how much picture there is: the height of a 16:9 picture with
  /// as many pixels. By its shorter side alone, a 4096x1152 share of a 32:9
  /// screen was "1080p" (Oct 5 2026), under half of what it carries; by its
  /// longer side, it would be "2160p", nearly twice.
  String? get qualityLabel {
    if (!hasResolution) return null;
    final side = sqrt(width! * height! * 9 / 16);
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
