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

  /// Every live connection belonging to [userId] — one per device they've
  /// joined from — with screenshares left out, since their audio is managed
  /// separately. Same rule [_applyStoredSettings] uses on join.
  ///
  /// Keying off the user rather than an exact identity is what makes a local
  /// mute take effect *now* in the two cases where the raw identity doesn't
  /// match a room key: a member muted from the members sidebar (which has only
  /// their user id) and a member connected from more than one device (where
  /// matching one identity left their other device audible).
  Iterable<RemoteParticipant> _connectionsOf(String userId) =>
      state.room?.remoteParticipants.values.where(
        (p) => ParticipantIdentity.isVoiceConnectionOf(p.identity, userId),
      ) ??
      const [];

  /// Locally mutes/unmutes a remote participant's audio (this user only).
  ///
  /// [target] may be a live LiveKit identity *or* a bare user id: the setting
  /// is stored per user (`userIdOf` returns the string unchanged when there is
  /// no device segment), so this works for a member who isn't in a voice
  /// channel right now. The preference is always persisted — live tracks are
  /// only touched for connections that exist, and `_applyStoredSettings` picks
  /// it up when they next join.
  Future<void> setParticipantMute(String target, bool muted) async {
    final userId = ParticipantIdentity.userIdOf(target);
    for (final participant in _connectionsOf(userId)) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) track.mediaStreamTrack.enabled = !muted;
      }
    }
    _appCubit.setParticipantSetting(userId, muted: muted);
  }

  /// Sets the local volume for a remote participant's audio (this user only).
  /// Persisted per user and applied on their next join — see
  /// [setParticipantMute] for why [target] may be a bare user id.
  Future<void> setParticipantVolume(String target, double volume) async {
    final userId = ParticipantIdentity.userIdOf(target);
    for (final participant in _connectionsOf(userId)) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        try {
          await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
        } catch (e) {
          debugPrint('setParticipantVolume error: $e');
        }
      }
    }
    _appCubit.setParticipantSetting(userId, volume: volume);
  }
}
