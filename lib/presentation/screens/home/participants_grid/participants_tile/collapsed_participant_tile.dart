import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/speaking_ring.dart';
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
  final VoidCallback onWatch;
  final VoidCallback onStopWatching;

  const CollapsedParticipantTile({
    super.key,
    required this.themeState,
    required this.videoTrack,
    required this.isSpeaking,
    required this.name,
    this.userId,
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
    final radius = BorderRadius.circular(14);

    return SpeakingRing(
      isSpeaking: isSpeaking,
      borderRadius: radius,
      bloom: 2.2,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: themeState.isDarkTheme
              ? themeState.bgSecondary
              : themeState.bgTertiary,
          borderRadius: radius,
          border: Border.all(
            // At rest the tile is edged, not outlined — the speaking ring is
            // what should read as a state change, not a thicker border.
            color: isSpeaking ? themeState.primary : themeState.borderElevated,
            width: isSpeaking ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (videoTrack != null)
                VideoTrackRenderer(videoTrack!, fit: VideoViewFit.contain)
              else if (!showWatchButton)
                AvatarPlaceholder(name: name, seed: userId),
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
      ),
    );
  }
}
