part of 'livekit_cubit.dart';

mixin _MediaControlsMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  Future<void> _syncMicrophoneTransmission({bool syncParticipants = false});
  void _syncParticipants();
  Future<void> _updateVoiceActivityMonitor();

  /// Toggles microphone. If deafened, un-deafens instead (restoring mic).
  Future<void> toggleMicrophone() async {
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
    await _setDeafened(!state.isDeafened);
  }

  /// True while something else in the app has been handed the microphone.
  bool _micSuspended = false;

  /// Whether the mic was live when it was suspended — so resuming never turns
  /// on a mic the user had deliberately muted.
  bool _micWasLive = false;

  /// Hands the microphone to something else in the app — today, the mic test
  /// in settings — and gives it back afterwards.
  ///
  /// Two captures of one device is not something to rely on. A Bluetooth
  /// headset has a single HFP stream, so the second capture simply takes it,
  /// and the call is left publishing silence with nothing in the code to
  /// notice. Muting first is honest about that, and it is what Discord's mic
  /// test does. `stopAudioCaptureOnMute` defaults to true, so this releases
  /// the hardware rather than only muting the stream.
  ///
  /// A no-op outside a call, where nothing holds the mic to begin with.
  Future<void> setMicrophoneSuspended(bool suspended) async {
    if (suspended == _micSuspended) return;
    if (state.room == null) return;
    _micSuspended = suspended;

    if (suspended) {
      _micWasLive = state.isMicEnabled && !state.isDeafened;
      if (!_micWasLive) return;
    } else if (!_micWasLive) {
      return;
    }

    final live = !suspended;
    _appCubit.setAudioEnabled(live);
    emit(state.copyWith(isMicEnabled: live));
    await _syncMicrophoneTransmission(syncParticipants: true);
  }

  Future<void> _setDeafened(bool deafened) async {
    final room = state.room;

    if (deafened) {
      if (room != null) {
        await room.localParticipant?.setMicrophoneEnabled(false);
        // Unsubscribe and silence all remote audio tracks.
        for (final participant in room.remoteParticipants.values) {
          for (final pub in participant.audioTrackPublications) {
            final track = pub.track;
            if (track != null) track.mediaStreamTrack.enabled = false;
            await pub.unsubscribe();
          }
        }
      }
      _appCubit.setAudioEnabled(false);
      emit(state.copyWith(isDeafened: true, isMicEnabled: false));
      // The mic track is gone — detach the voice-activity gate from it.
      await _updateVoiceActivityMonitor();
    } else {
      if (room != null) {
        // Re-subscribe all remote audio tracks, restoring per-participant settings.
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
            } else {
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
        // Restore mic
        await room.localParticipant?.setMicrophoneEnabled(true);
      }
      _appCubit.setAudioEnabled(true);
      emit(state.copyWith(isDeafened: false, isMicEnabled: true));
      await _syncMicrophoneTransmission();
    }

    if (room != null) _syncParticipants();
  }

  Future<void> setPushToTalkPressed(bool pressed) async {
    if (state.isPushToTalkPressed == pressed) return;
    emit(state.copyWith(isPushToTalkPressed: pressed));
    await _syncMicrophoneTransmission(syncParticipants: true);
  }

  Future<void> toggleCamera() async {
    final room = state.room;
    if (room == null) return;
    final next = !state.isCameraEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    _appCubit.setVideoEnabled(next);
    emit(state.copyWith(isCameraEnabled: next));
    _syncParticipants();
  }
}
