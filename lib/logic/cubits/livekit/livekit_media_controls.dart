part of 'livekit_cubit.dart';

mixin _MediaControlsMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  Future<void> _syncMicrophoneTransmission({bool syncParticipants = false});
  void _syncParticipants();

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
    } else {
      if (room != null) {
        // Re-subscribe all remote audio tracks, restoring per-participant settings.
        for (final participant in room.remoteParticipants.values) {
          final setting = _appCubit.state.participantSettings[
              ParticipantIdentity.userIdOf(participant.identity)];
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

