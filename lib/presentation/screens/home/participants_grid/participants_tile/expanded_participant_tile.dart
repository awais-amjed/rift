import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/video_stats_sampler.dart';
import '../../../../theme/app_motion.dart';
import 'avatar_placeholder.dart';
import 'participant_name_badge.dart';
import 'stop_watching_button.dart';
import 'stream_quality_badge.dart';
import 'stream_stats_overlay.dart';
import 'stream_stats_poller.dart';
import 'watch_stream_button.dart';

/// A participant filling the stage. Same content as the grid tile without the
/// card chrome, plus a stats overlay and controls that fade out while the
/// pointer is still — [showOverlays] drives that, and pointer activity is
/// reported through [onActivity].
class ExpandedParticipantTile extends StatelessWidget {
  static const _fade = AppMotion.enter;

  final VideoTrack? videoTrack;
  final String name;

  /// The *user* id, which picks the avatar's gradient so a participant looks
  /// the same here as in the sidebar. Not the LiveKit identity: that carries a
  /// device segment, so seeding with it gave the same person a different
  /// colour here, and a third one again for their screenshare.
  final String? userId;
  final bool isMicEnabled;
  final bool isMuted;
  final bool isScreenshare;
  final bool showWatchButton;
  final bool showStopButton;
  final bool showOverlays;
  final bool statsPinned;
  final VoidCallback onActivity;
  final VoidCallback onWatch;
  final VoidCallback onStopWatching;
  final ValueChanged<bool> onStatsPinnedChanged;

  /// How much of the top edge something else is covering right now — the
  /// call's top bar floating over the stage. The stats move down past it.
  final double topInset;

  const ExpandedParticipantTile({
    super.key,
    required this.videoTrack,
    required this.name,
    this.userId,
    required this.isMicEnabled,
    required this.isMuted,
    required this.isScreenshare,
    required this.showWatchButton,
    required this.showStopButton,
    required this.showOverlays,
    required this.statsPinned,
    required this.onActivity,
    required this.onWatch,
    required this.onStopWatching,
    required this.onStatsPinnedChanged,
    this.topInset = 0,
  });

  /// Wraps an overlay so it fades out *and* stops taking pointer events —
  /// an invisible button that still swallows clicks is worse than no button.
  Widget _fading({required bool visible, required Widget child}) =>
      AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: _fade,
        child: IgnorePointer(ignoring: !visible, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final showStats = context.select<AppCubit, bool>(
      (c) => c.state.showStreamStats,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (_) => onActivity(),
      onPointerHover: (_) => onActivity(),
      // Only someone else's share you are watching has receive stats.
      child: StreamStatsPoller(
        track: showStopButton ? videoTrack : null,
        builder: (context, stats) => _stage(stats, showStats: showStats),
      ),
    );
  }

  Widget _stage(VideoStreamStats? stats, {required bool showStats}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (videoTrack != null)
          VideoTrackRenderer(videoTrack!, fit: VideoViewFit.contain)
        else if (!showWatchButton)
          AvatarPlaceholder(name: name, seed: userId),
        if (showStats && stats != null)
          AnimatedPositioned(
            duration: _fade,
            curve: Curves.easeInOut,
            top: 12 + topInset,
            right: 12,
            // Pinned stats stay put even after the other overlays fade.
            child: _fading(
              visible: showOverlays || statsPinned,
              child: StreamStatsOverlay(
                stats: stats,
                onPinnedChanged: onStatsPinnedChanged,
              ),
            ),
          ),
        if (showWatchButton) WatchStreamButton(onTap: onWatch),
        if (showStopButton)
          Positioned(
            bottom: 12,
            right: 12,
            child: _fading(
              visible: showOverlays,
              child: StopWatchingButton(onTap: onStopWatching),
            ),
          ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _fading(
              visible: showOverlays,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Flexible(
                    child: ParticipantNameBadge(
                      name: name,
                      isMicEnabled: isMicEnabled,
                      isMuted: isMuted,
                      isScreenshare: isScreenshare,
                    ),
                  ),
                  StreamQualityBadge(stats: stats),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
