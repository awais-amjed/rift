import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/constants.dart';
import '../../../../common/speaking_ring.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/theme_context.dart';
import 'avatar_placeholder.dart';
import 'decrypted_video.dart';
import 'participant_name_badge.dart';
import 'shape_reporting_video.dart';
import 'share_paused_notice.dart';
import 'stream_fullscreen_button.dart';
import 'stream_quality_badge.dart';
import 'stream_stats_poller.dart';
import 'watch_stream_button.dart';

/// A participant as they appear in the grid: video or avatar in a rounded
/// card, name badge always visible, and a speaking ring that lights up.
class CollapsedParticipantTile extends StatelessWidget {
  final VideoTrack? videoTrack;
  final bool isSpeaking;
  final String name;

  /// The *user* id, which picks the avatar's gradient so a participant looks
  /// the same here as in the sidebar. Not the LiveKit identity: that carries a
  /// device segment, so seeding with it gave the same person a different
  /// colour here, and a third one again for their screenshare.
  final String userId;
  final bool isMicEnabled;
  final bool isMuted;
  final bool isDeafened;
  final bool isScreenshare;

  /// The stream's shared window is minimised, so the picture is the last
  /// frame, or there is none yet — see [SharePausedNotice].
  final bool isPaused;

  /// What the sharer says the stream is sent at ("1080p · 60fps"), which the
  /// badge shows in place of the measured rate. Null for anything else.
  final String? sentQuality;
  final bool showWatchButton;

  /// Someone else's stream with its picture here, which has receive stats.
  final bool isWatching;

  /// Opens the stream full screen; null for a tile with no button for it.
  final VoidCallback? onFullscreen;
  final VoidCallback onWatch;

  /// Told the video's shape when one arrives. Null for tiles whose box does
  /// not follow the picture.
  final ValueChanged<double>? onAspectRatio;

  const CollapsedParticipantTile({
    super.key,
    required this.videoTrack,
    required this.isSpeaking,
    required this.name,
    required this.userId,
    required this.isMicEnabled,
    required this.isMuted,
    this.isDeafened = false,
    required this.isScreenshare,
    this.isPaused = false,
    this.sentQuality,
    required this.showWatchButton,
    required this.isWatching,
    this.onFullscreen,
    required this.onWatch,
    this.onAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);

    return SpeakingRing(
      isSpeaking: isSpeaking,
      borderRadius: radius,
      bloom: 2.2,
      child: AnimatedContainer(
        duration: AppMotion.state,
        decoration: BoxDecoration(
          color: themeState.callTileBg,
          borderRadius: radius,
          // The same hairline speaking or not. Speech is the ring outside
          // the tile; a border swapping from 1px to 2px nudged the video
          // inside by a pixel every time someone started talking.
          border: Border.all(color: themeState.borderElevated),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(K.radiusCard - 1),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (videoTrack != null && onAspectRatio != null)
                DecryptedVideo(
                  track: videoTrack!,
                  child: ShapeReportingVideo(
                    key: ObjectKey(videoTrack),
                    track: videoTrack!,
                    onAspectRatio: onAspectRatio!,
                  ),
                )
              else if (videoTrack != null)
                DecryptedVideo(
                  track: videoTrack!,
                  child: VideoTrackRenderer(
                    videoTrack!,
                    fit: VideoViewFit.contain,
                  ),
                )
              else if (!showWatchButton && !isPaused)
                AvatarPlaceholder(name: name, userId: userId),
              // Over the last frame, or in place of a first one: a share started
              // on a minimised window has no picture until the window is opened.
              if (isPaused && !showWatchButton) const SharePausedNotice(),
              if (showWatchButton) WatchStreamButton(onTap: onWatch),
              if (onFullscreen != null)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: StreamFullscreenButton(
                    isFullscreen: false,
                    onTap: onFullscreen!,
                  ),
                ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                // Only someone else's share you are watching has receive
                // stats; the poller does nothing for anything else.
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: StreamStatsPoller(
                    track: isWatching ? videoTrack : null,
                    builder: (context, stats) => Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Flexible(
                          child: ParticipantNameBadge(
                            name: name,
                            isMicEnabled: isMicEnabled,
                            isMuted: isMuted,
                            isDeafened: isDeafened,
                            isScreenshare: isScreenshare,
                          ),
                        ),
                        StreamQualityBadge(stats: stats, sent: sentQuality),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
