part of 'livekit_cubit.dart';

mixin _ScreenshareMixin on Cubit<LiveKitState> {
  void _syncParticipants();

  /// Subscribes to a participant's screenshare tracks.
  Future<void> subscribeToScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      debugPrint('Participant $identity not found');
      return;
    }

    var subscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.subscribe();
          pub.setVideoQuality(VideoQuality.HIGH);
          debugPrint('✓ Subscribed to screenshare video from $identity');
          subscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to subscribe to screenshare video: $e');
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.subscribe();
          debugPrint('✓ Subscribed to screenshare audio from $identity');
          subscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to subscribe to screenshare audio: $e');
        }
      }
    }

    if (subscribedAny) {
      final updated = Set<String>.from(state.subscribedScreenshares)
        ..add(identity);
      emit(state.copyWith(subscribedScreenshares: updated));
      _syncParticipants();
    } else {
      debugPrint('No screenshare tracks found for $identity');
    }
  }

  /// Unsubscribes from a participant's screenshare tracks.
  Future<void> unsubscribeFromScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) return;

    var unsubscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.unsubscribe();
          debugPrint('✓ Unsubscribed from screenshare video from $identity');
          unsubscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to unsubscribe from screenshare video: $e');
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.unsubscribe();
          debugPrint('✓ Unsubscribed from screenshare audio from $identity');
          unsubscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to unsubscribe from screenshare audio: $e');
        }
      }
    }

    if (unsubscribedAny) {
      final updated = Set<String>.from(state.subscribedScreenshares)
        ..remove(identity);
      emit(state.copyWith(subscribedScreenshares: updated));
      _syncParticipants();
    }
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
            ScreenShareCaptureOptions(useiOSBroadcastExtension: false),
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
      debugPrint('✗ Screen share failed: $e');
    }
  }
}
