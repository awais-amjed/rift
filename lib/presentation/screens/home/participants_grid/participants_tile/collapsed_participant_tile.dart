import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import 'avatar_placeholder.dart';
import 'participant_name_badge.dart';
import 'stop_watching_button.dart';
import 'watch_stream_button.dart';

/// A participant as they appear in the grid: video or avatar in a rounded
/// card, name badge always visible, and a speaking ring that lights up.
class CollapsedParticipantTile extends StatelessWidget {
  final ThemeState themeState;
  final VideoTrack? videoTrack;
  final bool isSpeaking;
  final String name;
  final bool isMicEnabled;
  final bool isMuted;
  final bool isScreenshare;
  final bool showWatchButton;
  final bool showStopButton;
  final VoidCallback onWatch;
  final VoidCallback onStopWatching;

  const CollapsedParticipantTile({
    super.key,
    required this.themeState,
    required this.videoTrack,
    required this.isSpeaking,
    required this.name,
    required this.isMicEnabled,
    required this.isMuted,
    required this.isScreenshare,
    required this.showWatchButton,
    required this.showStopButton,
    required this.onWatch,
    required this.onStopWatching,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: themeState.isDarkTheme
            ? themeState.bgSecondary
            : themeState.bgTertiary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeaking ? themeState.primary : themeState.borderPrimary,
          width: isSpeaking ? 2 : 1,
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: themeState.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoTrack != null)
              VideoTrackRenderer(videoTrack!, fit: VideoViewFit.contain)
            else if (!showWatchButton)
              AvatarPlaceholder(name: name, isDark: themeState.isDarkTheme),
            if (showWatchButton) WatchStreamButton(onTap: onWatch),
            if (showStopButton)
              Positioned(
                bottom: 12,
                right: 12,
                child: StopWatchingButton(onTap: onStopWatching),
              ),
            Positioned(
              bottom: 12,
              left: 12,
              child: ParticipantNameBadge(
                name: name,
                isMicEnabled: isMicEnabled,
                isMuted: isMuted,
                isScreenshare: isScreenshare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
