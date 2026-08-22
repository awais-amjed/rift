part of 'livekit_cubit.dart';

mixin _MediaControlsMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  Future<void> _syncMicrophoneTransmission({bool syncParticipants = false});
  void _syncParticipants();
  Future<void> _updateVoiceActivityMonitor();

  /// Toggles microphone. If deafened, un-deafens instead (restoring mic).
  ///
  /// Does nothing while a moderator holds the mic — the toggle would record an
  /// intent the user can't see the effect of, and the button is disabled to
  /// match. Their pre-existing choice is what gets restored on release.
  Future<void> toggleMicrophone() async {
    if (state.isModerated) return;
    if (state.isDeafened) {
      await _setDeafened(false);
      return;
    }
    final next = !state.isMicEnabled;
    _appCubit.setAudioEnabled(next);
    emit(state.copyWith(isMicEnabled: next));
    await _syncMicrophoneTransmission(syncParticipants: true);
  }

  /// Toggles deafen: mutes mic and silences all remote audio, or reverses that.
  Future<void> toggleDeafen() async {
    if (state.isServerDeafened) return;
    await _setDeafened(!state.isDeafened);
  }

  /// Sets the user's *own* deafen.
  ///
  /// This deliberately no longer writes [LiveKitState.isMicEnabled]. It used to
  /// force it false on the way in and true on the way out, which quietly threw
  /// away the user's own choice: mute, deafen, undeafen, and the mic came back
  /// on by itself. `_shouldTransmitMic` already refuses to transmit while
  /// deafened, so the intent can just be left alone and honoured on release.
  Future<void> _setDeafened(bool deafened) async {
    final wasDeafened = state.isDeafenedEffective;
    emit(state.copyWith(isDeafened: deafened));

    if (state.isDeafenedEffective) {
      if (!wasDeafened) await _silenceRemoteAudio();
    } else if (wasDeafened) {
      await _restoreRemoteAudio();
    }

    // Republishes or drops the mic track according to the whole picture — own
    // toggle, own deafen, moderation, push-to-talk.
    await _syncMicrophoneTransmission();
    await _updateVoiceActivityMonitor();
    if (state.room != null) _syncParticipants();
  }

  /// Unsubscribes from every remote audio track, so nothing is even received.
  Future<void> _silenceRemoteAudio() async {
    final room = state.room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) track.mediaStreamTrack.enabled = false;
        await pub.unsubscribe();
      }
    }
  }

  /// Re-subscribes to remote audio and reapplies each participant's stored
  /// local mute and volume. Shared by un-deafening yourself and by a moderator
  /// lifting a server deafen — both have to hand the audio back the same way.
  Future<void> _restoreRemoteAudio() async {
    final room = state.room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      final setting =
          _appCubit.state.participantSettings[ParticipantIdentity.userIdOf(
            participant.identity,
          )];
      final isMuted = setting?.muted ?? false;
      for (final pub in participant.audioTrackPublications) {
        await pub.subscribe();
        final track = pub.track;
        if (track == null) continue;
        if (isMuted) {
          track.mediaStreamTrack.enabled = false;
          continue;
        }
        track.mediaStreamTrack.enabled = true;
        final volume = setting?.volume ?? 1.0;
        if (volume != 1.0) {
          try {
            await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
          } catch (e) {
            HelperMethods.printDebug('setVolume error: $e');
          }
        }
      }
    }
  }

  /// How long the mic keeps transmitting after the key comes up.
  ///
  /// Muting the instant the key is released cuts the end off whatever was
  /// being said — `LocalTrack.mute` disables the media stream track straight
  /// away, so everything still in the encoder and on its way to the server is
  /// lost, and the server stops forwarding the moment the mute signal lands.
  /// The signal travels over the reliable socket while the audio does not, so
  /// it can arrive first. Holding transmission open for a moment lets all of
  /// that drain before anything is torn down.
  static const Duration _pushToTalkReleaseDelay = Duration(milliseconds: 200);

  Timer? _pushToTalkReleaseTimer;

  /// Cancels a pending release, so nothing is torn down out from under a
  /// caller that is about to change the mic itself.
  void _cancelPushToTalkRelease() {
    _pushToTalkReleaseTimer?.cancel();
    _pushToTalkReleaseTimer = null;
  }

  Future<void> setPushToTalkPressed(bool pressed) async {
    if (pressed) {
      // Pressing again inside the release window: the mic never stopped, so
      // there is nothing to restart, just a teardown to call off. Auto-repeat
      // sends this many times over while the key is held.
      _cancelPushToTalkRelease();
      if (state.isPushToTalkPressed) return;
      emit(state.copyWith(isPushToTalkPressed: true));
      await _syncMicrophoneTransmission(syncParticipants: true);
      return;
    }

    if (!state.isPushToTalkPressed || _pushToTalkReleaseTimer != null) return;

    _pushToTalkReleaseTimer = Timer(_pushToTalkReleaseDelay, () {
      _pushToTalkReleaseTimer = null;
      // The cubit can be closed, or the key pressed again and the state
      // already moved on, between scheduling this and it firing.
      if (isClosed || !state.isPushToTalkPressed) return;
      emit(state.copyWith(isPushToTalkPressed: false));
      unawaited(_syncMicrophoneTransmission(syncParticipants: true));
    });
  }

  Future<void> toggleCamera() async {
    final room = state.room;
    if (room == null) return;
    final next = !state.isCameraEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    _appCubit.setVideoEnabled(next);
    emit(state.copyWith(isCameraEnabled: next));
    _syncParticipants();
    // After the track, not before: switching on is what prompts for CAMERA,
    // and the foreground service may only claim the camera type once that has
    // been granted. Without the type Android cuts the picture the moment the
    // app goes to the background, leaving a video call that is audio-only to
    // everyone else.
    unawaited(CallForegroundService.cameraChanged());
  }
}
