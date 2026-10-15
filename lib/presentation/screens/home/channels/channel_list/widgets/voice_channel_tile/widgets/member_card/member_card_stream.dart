import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../../../../data/constants.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../../../../logic/services/share_presence.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/media_colors.dart';
import '../../../../../../../../theme/theme_context.dart';
import '../../../../../../participants_grid/participants_tile/decrypted_video.dart';
import '../../../../../../participants_grid/participants_tile/stream_watchers.dart';

/// What somebody in this device's call is sharing: the picture, while it is
/// being watched here; the quality it is sent at and whether it carries
/// sound; who is watching it; and an app's sound shared on its own.
///
/// No window or app name for a screen: a share does not send one, and a
/// window's title is too often something private to start sending.
///
/// Draws nothing for a call this device is not in, which is where none of
/// this has arrived.
class MemberCardStream extends StatelessWidget {
  final String userId;

  /// Space under it when it draws something, for the button that follows —
  /// carried here because a gap of the card's own would stand there empty
  /// when it draws nothing.
  final double gapBelow;

  const MemberCardStream({super.key, required this.userId, this.gapBelow = 0});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final screen = context.select<LiveKitCubit, String?>(
      (cubit) => screenOf(
        cubit.state.participants,
        userId,
        identityOf: (p) => p.identity,
        publishesScreenshare: (p) => p.videoTrackPublications.any(
          (pub) => pub.source == TrackSource.screenShareVideo,
        ),
      ),
    );
    final soundLabel = context.select<AppCubit, String?>(
      (cubit) => cubit.state.participants
          .where((p) => p.isSoundShare && p.userId == userId)
          .firstOrNull
          ?.shareLabel,
    );
    if (screen == null && soundLabel == null) return const SizedBox.shrink();

    // No spacing of the column's own: the preview and the watchers draw
    // nothing until there is something to show, and a gap kept for each
    // left the card uneven.
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (screen != null) ...[
          _Preview(identity: screen),
          Row(
            spacing: 8,
            children: [
              Expanded(child: _Details(identity: screen)),
              StreamWatchers(shareIdentity: screen),
            ],
          ),
        ],
        if (screen != null && soundLabel != null) const SizedBox(height: 8),
        if (soundLabel != null)
          Row(
            spacing: 5,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: theme.accentBright,
              ),
              Flexible(
                child: Text(
                  soundLabel.isEmpty
                      ? 'Sharing sound'
                      : 'Sharing sound from $soundLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary.copyWith(color: theme.textSecondary),
                ),
              ),
            ],
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: gapBelow),
      child: lines,
    );
  }
}

/// The stream itself, small — only while this device is watching it. Opening
/// it just to fill the card would pull the whole picture down for a glance.
class _Preview extends StatelessWidget {
  final String identity;

  const _Preview({required this.identity});

  @override
  Widget build(BuildContext context) {
    final track = context.select<LiveKitCubit, VideoTrack?>((cubit) {
      final lk = cubit.state;
      if (!lk.subscribedScreenshares.contains(identity)) return null;
      final room = lk.room;
      final Participant? participant =
          identity == room?.localParticipant?.identity
          ? room?.localParticipant
          : room?.remoteParticipants[identity];
      final pub = participant?.videoTrackPublications
          .where((p) => p.source == TrackSource.screenShareVideo)
          .firstOrNull;
      final t = pub?.track;
      return t is VideoTrack ? t : null;
    });
    if (track == null) return const SizedBox.shrink();
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: MediaColors.videoGround,
          child: DecryptedVideo(
            track: track,
            child: VideoTrackRenderer(track, fit: VideoViewFit.contain),
          ),
        ),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: preview);
  }
}

/// "1080p · 60fps · With sound": what the sharer's app says it is sending,
/// and whether the stream carries sound.
class _Details extends StatelessWidget {
  final String identity;

  const _Details({required this.identity});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final quality = context.select<AppCubit, String?>(
      (cubit) => cubit.state.participants
          .where((p) => p.identity == identity)
          .firstOrNull
          ?.shareQuality,
    );
    final sound = context.select<LiveKitCubit, bool>((cubit) {
      final room = cubit.state.room;
      final Participant? participant =
          identity == room?.localParticipant?.identity
          ? room?.localParticipant
          : room?.remoteParticipants[identity];
      return participant?.audioTrackPublications.any(
            (pub) => pub.source == TrackSource.screenShareAudio,
          ) ??
          false;
    });
    final parts = [
      if (quality != null && quality.isNotEmpty) quality,
      sound ? 'With sound' : 'No sound',
    ];
    return Text(
      parts.join(' · '),
      style: AppText.secondary.copyWith(color: theme.textTertiary),
    );
  }
}
