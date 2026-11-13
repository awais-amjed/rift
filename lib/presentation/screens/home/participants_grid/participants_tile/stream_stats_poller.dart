import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../logic/services/rust_watch.dart';
import '../../../../../logic/services/video_stats_sampler.dart';
import '../../../../../logic/services/video_stream_stats.dart';

/// Polls a watched stream's receive stats once a second and hands them to
/// [builder]. One poller feeds both the quality badge and the stats card, so
/// showing both does not ask WebRTC twice.
///
/// The numbers come from [track]'s receiver, or for a share the Rust watch
/// connection holds, which has no track in the call, from Rust by its
/// [rustShare] identity. With neither — a camera, your own share, a share not
/// yet watched — nothing is polled and [builder] gets null.
class StreamStatsPoller extends StatefulWidget {
  final VideoTrack? track;
  final String? rustShare;
  final Widget Function(BuildContext context, VideoStreamStats? stats) builder;

  const StreamStatsPoller({
    super.key,
    required this.track,
    this.rustShare,
    required this.builder,
  });

  @override
  State<StreamStatsPoller> createState() => _StreamStatsPollerState();
}

class _StreamStatsPollerState extends State<StreamStatsPoller> {
  static const _pollInterval = Duration(seconds: 1);

  VideoStatsSampler _sampler = VideoStatsSampler();
  Timer? _timer;
  VideoStreamStats? _stats;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(StreamStatsPoller oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A sampler's rates are differences against its last poll, so a new
    // track starts from a new one.
    if (oldWidget.track != widget.track ||
        oldWidget.rustShare != widget.rustShare) {
      _restart();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    _sampler = VideoStatsSampler();
    _stats = null;
    if (widget.track == null && widget.rustShare == null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final track = widget.track;
    final rustShare = widget.rustShare;
    if (rustShare != null) {
      final inbound = await RustWatch.stats(rustShare);
      if (!mounted || widget.rustShare != rustShare) return;
      _show(inbound == null ? null : _sampler.sampleInbound(inbound));
      return;
    }
    final receiver = track?.receiver;
    if (receiver == null) return;
    try {
      final reports = await receiver.getStats();
      if (!mounted || widget.track != track) return;
      _show(_sampler.sample(reports));
    } catch (_) {
      // The track may not be subscribed yet, or stats may be unavailable.
      // The next poll will pick them up.
    }
  }

  void _show(VideoStreamStats? stats) {
    if (stats != null) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _stats);
}
