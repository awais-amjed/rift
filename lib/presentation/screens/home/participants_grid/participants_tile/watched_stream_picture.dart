import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/watched_picture.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import 'decrypted_video.dart';
import 'stream_texture_view.dart';

/// A stream this device is watching, drawn away from the stage: in a member
/// card, or floating while the call is not on screen. Either the room's track
/// or, through the Rust watch connection, the runner's texture.
///
/// Draws nothing for a stream that is not being watched here: opening one
/// just to fill a small box would pull the whole picture down for a glance.
class WatchedStreamPicture extends StatelessWidget {
  final String identity;

  /// Puts the picture in its box, only when there is one to draw.
  final Widget Function(Widget picture) frame;

  const WatchedStreamPicture({
    super.key,
    required this.identity,
    required this.frame,
  });

  @override
  Widget build(BuildContext context) {
    final picture = context.select<LiveKitCubit, WatchedPicture?>(
      (cubit) => cubit.state.watchedPictures[identity],
    );
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
    if (track == null && picture == null) return const SizedBox.shrink();
    return frame(
      picture != null
          ? StreamTextureView(picture: picture)
          : DecryptedVideo(
              track: track!,
              child: VideoTrackRenderer(track, fit: VideoViewFit.contain),
            ),
    );
  }
}
