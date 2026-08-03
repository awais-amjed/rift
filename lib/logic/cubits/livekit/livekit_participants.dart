part of 'livekit_cubit.dart';

mixin _ParticipantMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  ServerCubit? get _serverCubit;

  /// Mutes/unmutes a participant for everyone in the room (requires is_channel_manager).
  /// Server-side moderation: persistently mute/deafen a user for everyone.
  /// [participantIdentity] may be a screenshare or multi-device identity — the
  /// user id is extracted from it.
  Future<bool> moderateParticipant({
    required String participantIdentity,
    bool? muted,
    bool? deafened,
  }) async {
    final serverCubit = _serverCubit;
    if (serverCubit == null) return false;

    final userId = ParticipantIdentity.userIdOf(participantIdentity);

    final response = await serverCubit.moderateUser(
      userId: userId,
      isMuted: muted,
      isDeafened: deafened,
    );
    if (!response.success) {
      debugPrint('moderateParticipant error: ${response.error}');
    }
    return response.success;
  }

  /// Locally mutes/unmutes a remote participant's audio (this user only).
  ///
  /// [identity] may be a live LiveKit identity *or* a bare user id: the
  /// setting is stored per user (`userIdOf` returns the string unchanged when
  /// there is no device segment), so this works for a member who isn't in a
  /// voice channel right now. The preference is always persisted — the live
  /// track is only touched when they happen to be connected, and
  /// `_applyStoredSettings` picks it up when they next join.
  Future<void> setParticipantMute(String identity, bool muted) async {
    final participant = state.room?.remoteParticipants[identity];
    if (participant != null) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) track.mediaStreamTrack.enabled = !muted;
      }
    }
    _appCubit.setParticipantSetting(
      ParticipantIdentity.userIdOf(identity),
      muted: muted,
    );
  }

  /// Sets the local volume for a remote participant's audio (this user only).
  /// Persisted per user and applied on their next join — see
  /// [setParticipantMute] for why [identity] may be a bare user id.
  Future<void> setParticipantVolume(String identity, double volume) async {
    final participant = state.room?.remoteParticipants[identity];
    if (participant != null) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) {
          try {
            await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
          } catch (e) {
            debugPrint('setParticipantVolume error: $e');
          }
        }
      }
    }
    _appCubit.setParticipantSetting(
      ParticipantIdentity.userIdOf(identity),
      volume: volume,
    );
  }
}
