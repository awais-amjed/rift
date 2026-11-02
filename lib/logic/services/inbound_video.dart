/// One poll of a received picture's own counters, wherever it is received:
/// the call's connection (a WebRTC stats report, [VideoStatsSampler.sample])
/// or the Rust watch connection (`RustWatch.stats`). Cumulative, as WebRTC
/// keeps them, so the sampler turns two polls into rates.
///
/// Every field but the time may be missing: a report can arrive before the
/// value it carries exists, and the stats card leaves out a row it has no
/// number for.
class InboundVideo {
  /// When the counters were taken, in milliseconds.
  final double timestampMs;
  final int? width;
  final int? height;
  final double? framesDecoded;
  final int? framesDropped;

  /// libwebrtc's own rate, shown until two polls give one.
  final double? framesPerSecond;
  final double? bytesReceived;
  final double? packetsReceived;

  /// Lost so far, not lately: WebRTC's running count, which can fall as
  /// late packets turn up.
  final int? packetsLost;
  final double? jitterMs;

  /// "VP9", "H264", without the `video/`.
  final String? codec;
  final double? rttMs;

  const InboundVideo({
    required this.timestampMs,
    this.width,
    this.height,
    this.framesDecoded,
    this.framesDropped,
    this.framesPerSecond,
    this.bytesReceived,
    this.packetsReceived,
    this.packetsLost,
    this.jitterMs,
    this.codec,
    this.rttMs,
  });
}
