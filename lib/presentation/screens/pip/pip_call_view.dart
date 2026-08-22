import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/services/participant_video.dart';
import '../../../logic/services/pip_focus.dart';
import '../../../logic/services/room_tiles.dart';
import 'pip_audio_card.dart';

/// The whole app, at the size of a floating window.
///
/// A picture-in-picture window is a few hundred pixels with no room for
/// chrome, so this is not the call's UI made smaller — it is the one thing
/// from the call worth seeing, and nothing else. Which one that is comes from
/// [pipFocus]; there are no controls because the window has no space for a
/// target a thumb could hit, and the notification already carries them.
///
/// Tapping the window is Android's own gesture for restoring the app, so
/// getting back to the full call needs nothing from us.
class PipCallView extends StatelessWidget {
  const PipCallView({super.key});

  @override
  Widget build(BuildContext context) {
    // Material, not a bare ColoredBox: this view is mounted above the
    // navigator, where there is no Scaffold to inherit a text style from, and
    // text without one renders in Flutter's yellow-underlined debug style.
    // Black rather than the theme's background because this is a video
    // surface, and letterboxing should read as the edge of the picture.
    return Material(
      color: Colors.black,
      child: BlocBuilder<LiveKitCubit, LiveKitState>(
        builder: (context, state) {
          final track = _focusTrack(state);
          if (track == null) return const PipAudioCard();
          return VideoTrackRenderer(track, fit: VideoViewFit.contain);
        },
      ),
    );
  }

  /// The video to fill the window with, or null if there is none left.
  ///
  /// Null is reachable even though the window is only armed while there *is*
  /// video: a camera can go off while the app is already floating, and the
  /// window stays until the user puts it away.
  VideoTrack? _focusTrack(LiveKitState state) {
    final focus = pipFocus(
      roomVoiceTiles(state.participants),
      isLocal: (p) => p is LocalParticipant,
      isSpeaking: (p) => p.isSpeaking,
      hasVideo: (tile) =>
          _trackOf(tile.participant, tile.isScreenshare) != null,
    );
    if (focus == null) return null;
    return _trackOf(focus.participant, focus.isScreenshare);
  }

  VideoTrack? _trackOf(Participant participant, bool isScreenshare) {
    final track = ParticipantVideo.activePublication(
      participant.videoTrackPublications,
      isScreenshare: isScreenshare,
    )?.track;
    return track is VideoTrack ? track : null;
  }
}
