import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import 'avatar_placeholder.dart';
import 'participant_name_badge.dart';
import 'stop_watching_button.dart';
import 'stream_stats_overlay.dart';
import 'watch_stream_button.dart';

/// A participant filling the stage. Same content as the grid tile without the
/// card chrome, plus a stats overlay and controls that fade out while the
/// pointer is still — [showOverlays] drives that, and pointer activity is
/// reported through [onActivity].
class ExpandedParticipantTile extends StatelessWidget {
  static const _fade = Duration(milliseconds: 300);

  final ThemeState themeState;
  final VideoTrack? videoTrack;
  final String name;
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

  const ExpandedParticipantTile({
    super.key,
    required this.themeState,
    required this.videoTrack,
    required this.name,
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (_) => onActivity(),
      onPointerHover: (_) => onActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            VideoTrackRenderer(videoTrack!, fit: VideoViewFit.contain)
          else if (!showWatchButton)
            AvatarPlaceholder(name: name, isDark: themeState.isDarkTheme),
          if (showStopButton && videoTrack != null)
            Positioned(
              top: 12,
              right: 12,
              // Pinned stats stay put even after the other overlays fade.
              child: _fading(
                visible: showOverlays || statsPinned,
                child: StreamStatsOverlay(
                  track: videoTrack!,
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
            child: _fading(
              visible: showOverlays,
              child: ParticipantNameBadge(
                name: name,
                isMicEnabled: isMicEnabled,
                isMuted: isMuted,
                isScreenshare: isScreenshare,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
