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
  Future<void> setParticipantMute(String identity, bool muted) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
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
  Future<void> setParticipantVolume(String identity, double volume) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
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

