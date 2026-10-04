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
      HelperMethods.printDebug('moderateParticipant error: ${response.error}');
    }
    return response.success;
  }

  /// Every live audio track whose local mute and volume are stored under
  /// [key] — see [ParticipantIdentity.settingsKeyOf].
  ///
  /// Matched by key rather than identity, which is what makes a setting reach
  /// every device somebody is on, a member muted from the members sidebar
  /// (which has only their user id), and a share restarted with a new device
  /// segment. Same rule [_applyStoredSettings] uses on join.
  Iterable<rtc.MediaStreamTrack> _audioTracksFor(String key) sync* {
    final room = state.room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        final trackKey = ParticipantIdentity.settingsKeyOf(
          participant.identity,
          screenAudio: pub.source == TrackSource.screenShareAudio,
          localIdentity: room.localParticipant?.identity,
        );
        if (trackKey == key) yield track.mediaStreamTrack;
      }
    }
  }

  /// Locally mutes or unmutes whatever is stored under [key] (this listener
  /// only): a person's voice, or one of their shares.
  ///
  /// Each is stored apart from the others: a room where one member has music
  /// on should be able to turn the music down without also turning that
  /// member down. The preference is always persisted — live tracks are only
  /// touched where they exist, and `_applyStoredSettings` picks it up when
  /// they next join or share.
  void setMuteFor(String key, bool muted) {
    _appCubit.setParticipantSetting(key, muted: muted);
    _applySettingFor(key);
  }

  /// Sets the local volume of whatever is stored under [key] — see
  /// [setMuteFor]. Still silent while it is muted.
  Future<void> setVolumeFor(String key, double volume) async {
    _appCubit.setParticipantSetting(
      key,
      volume: volume.clamp(0.0, CallVolume.max),
    );
    _applySettingFor(key);
  }

  void _applySettingFor(String key) {
    // Stored for when the deafen lifts; nothing is playing to change now.
    if (state.isDeafenedEffective) return;
    final app = _appCubit.state;
    final setting = app.settingFor(key);
    for (final track in _audioTracksFor(key)) {
      _applyAudioSetting(track, setting, app.outputVolume);
    }
  }

  /// Locally mutes/unmutes a remote participant's voice (this user only).
  ///
  /// [target] may be a live LiveKit identity *or* a bare user id: the setting
  /// is stored per user (`userIdOf` returns the string unchanged when there is
  /// no device segment), so this works for a member who isn't in a voice
  /// channel right now.
  Future<void> setParticipantMute(String target, bool muted) async =>
      setMuteFor(ParticipantIdentity.userIdOf(target), muted);

  /// Sets the local volume of a remote participant's voice — see
  /// [setParticipantMute] for why [target] may be a bare user id.
  Future<void> setParticipantVolume(String target, double volume) =>
      setVolumeFor(ParticipantIdentity.userIdOf(target), volume);
}

/// Puts this device's mute and volume on one remote audio track, the volume
/// for every call ([output]) included — see [CallVolume.of].
///
/// A mute is also a volume of nothing. The SDK enables a remote track itself
/// as it starts it, just *after* telling us it subscribed, so a mute made of
/// `enabled` alone was undone the moment it was applied: a stored mute did not
/// hold, and your own stream's sound came back on and echoed.
void _applyAudioSetting(
  rtc.MediaStreamTrack track,
  ParticipantSetting setting,
  double output,
) {
  track.enabled = !setting.muted;
  rtc.Helper.setVolume(
    CallVolume.of(setting, output),
    track,
  ).catchError((Object e) => HelperMethods.printDebug('setVolume error: $e'));
}
