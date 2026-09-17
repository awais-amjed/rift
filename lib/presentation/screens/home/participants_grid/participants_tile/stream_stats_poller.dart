import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/services/video_stats_sampler.dart';

/// Polls a watched stream's receive stats once a second and hands them to
/// [builder]. One poller feeds both the quality badge and the stats card, so
/// showing both does not ask WebRTC twice.
///
/// With no [track] — a camera, your own share, a share not yet watched —
/// nothing is polled and [builder] gets null.
class StreamStatsPoller extends StatefulWidget {
  final VideoTrack? track;
  final Widget Function(BuildContext context, VideoStreamStats? stats) builder;

  const StreamStatsPoller({
    super.key,
    required this.track,
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
    if (oldWidget.track != widget.track) _restart();
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
    if (widget.track == null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final track = widget.track;
    final receiver = track?.receiver;
    if (receiver == null) return;
    try {
      final reports = await receiver.getStats();
      if (!mounted || widget.track != track) return;
      final stats = _sampler.sample(reports);
      if (stats != null) setState(() => _stats = stats);
    } catch (_) {
      // The track may not be subscribed yet, or stats may be unavailable.
      // The next poll will pick them up.
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _stats);
}
