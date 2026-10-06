part of 'livekit_cubit.dart';

mixin _ScreenshareMixin on Cubit<LiveKitState> {
  void _syncParticipants();

  /// Watching is published, so the sharer and the others watching hear it.
  Future<void> _publishSelfState();

  /// Subscribes to a participant's screenshare tracks.
  Future<void> subscribeToScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    // Your own stream from a phone: the picture is already here, so watching
    // it is only a choice to show it, as it is on a desktop, where it comes
    // back as a connection like anyone else's and can be hidden the same way.
    if (identity == room.localParticipant?.identity) {
      _setWatching(identity, true);
      return;
    }

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      HelperMethods.printDebug('[LiveKit] Participant $identity not found');
      return;
    }

    // Watching is recorded before the subscription is asked for, not after.
    // Starting to watch also opens the stream full size, and the tile that
    // opens checks this set as it appears — finding the stream not yet in
    // it, it unsubscribed from what had just been asked for, and the stage
    // showed the sharer's avatar instead of their screen.
    final wasWatching = state.subscribedScreenshares.contains(identity);
    if (!wasWatching) {
      emit(
        state.copyWith(
          subscribedScreenshares: {...state.subscribedScreenshares, identity},
        ),
      );
    }

    var subscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.subscribe();
          await pub.setVideoQuality(VideoQuality.HIGH);
          HelperMethods.printDebug(
            '[LiveKit] Subscribed to screenshare video from $identity',
          );
          subscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to subscribe to screenshare video: $e',
          );
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.subscribe();
          HelperMethods.printDebug(
            '[LiveKit] Subscribed to screenshare audio from $identity',
          );
          subscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to subscribe to screenshare audio: $e',
          );
        }
      }
    }

    if (subscribedAny) {
      _syncParticipants();
      unawaited(_publishSelfState());
    } else {
      HelperMethods.printDebug(
        '[LiveKit] No screenshare tracks found for $identity',
      );
      if (!wasWatching) {
        emit(
          state.copyWith(
            subscribedScreenshares: Set<String>.from(
              state.subscribedScreenshares,
            )..remove(identity),
          ),
        );
      }
    }
  }

  /// Unsubscribes from a participant's screenshare tracks.
  Future<void> unsubscribeFromScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    if (identity == room.localParticipant?.identity) {
      _setWatching(identity, false);
      return;
    }

    final participant = room.remoteParticipants[identity];
    if (participant == null) return;

    var unsubscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.unsubscribe();
          HelperMethods.printDebug(
            '[LiveKit] Unsubscribed from screenshare video from $identity',
          );
          unsubscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to unsubscribe from screenshare video: $e',
          );
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.unsubscribe();
          HelperMethods.printDebug(
            '[LiveKit] Unsubscribed from screenshare audio from $identity',
          );
          unsubscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to unsubscribe from screenshare audio: $e',
          );
        }
      }
    }

    if (unsubscribedAny) {
      final updated = Set<String>.from(state.subscribedScreenshares)
        ..remove(identity);
      emit(state.copyWith(subscribedScreenshares: updated));
      _syncParticipants();
      unawaited(_publishSelfState());
    }
  }

  /// Stops watching every stream — the call bar's Stop watching, which takes
  /// the place of Leave while anything is watched. One press puts them all
  /// away, so the button turns back into Leave rather than staying put for a
  /// second stream the user may not have noticed was still open.
  Future<void> stopWatchingAll() async {
    for (final identity in state.subscribedScreenshares.toList()) {
      await unsubscribeFromScreenshare(identity);
    }
    // A stream whose sharer has just gone has nothing left to unsubscribe
    // from, and would keep the button on Stop watching for nothing.
    if (state.subscribedScreenshares.isNotEmpty) {
      emit(state.copyWith(subscribedScreenshares: const {}));
      _syncParticipants();
      unawaited(_publishSelfState());
    }
  }

  /// Records watching [identity] or not, with nothing to subscribe to.
  void _setWatching(String identity, bool watching) {
    final updated = Set<String>.from(state.subscribedScreenshares);
    if (!(watching ? updated.add(identity) : updated.remove(identity))) return;
    emit(state.copyWith(subscribedScreenshares: updated));
    _syncParticipants();
    unawaited(_publishSelfState());
  }

  /// Toggle screen sharing on/off.
  Future<void> toggleScreenShare({
    ScreenShareCaptureOptions? captureOptions,
  }) async {
    final room = state.room;
    if (room == null) return;

    final next = !state.isScreenSharing;
    try {
      await room.localParticipant?.setScreenShareEnabled(
        next,
        screenShareCaptureOptions:
            captureOptions ??
            const ScreenShareCaptureOptions(useiOSBroadcastExtension: false),
      );
      emit(state.copyWith(isScreenSharing: next));
      _syncParticipants();
    } catch (e) {
      // Logged rather than stored. This wrote to the state's error field
      // without moving the connection out of `connected`, and the error screen
      // only renders in the error state — so the message was never shown to
      // anyone. Surfacing a failed screen share properly needs its own channel;
      // pretending it is a connection failure would replace a live call with an
      // error page.
      HelperMethods.printDebug('[LiveKit] Screen share failed: $e');
    }
  }

  /// Silences the shares whose owner is not in the call, and lets them be
  /// heard again once the owner is back — see [sharesWithoutOwner]. Their
  /// tiles are left out of the call already; a picture nobody draws is
  /// paused by adaptive streaming, but sound plays whether it is watched or
  /// not, so the server is told to stop sending it.
  void _holdSharesWithoutOwner(Room room, Set<String> ownerless) {
    for (final participant in room.remoteParticipants.values) {
      if (!ParticipantIdentity.isShare(participant.identity)) continue;
      final play = !ownerless.contains(participant.identity);
      for (final pub in participant.audioTrackPublications) {
        if (!pub.subscribed || pub.enabled == play) continue;
        unawaited(play ? pub.enable() : pub.disable());
      }
    }
  }
}
