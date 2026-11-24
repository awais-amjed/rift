part of 'livekit_cubit.dart';

/// Clipping: keeping the last stretch of the call for the clip shortcut, and
/// telling the call who does it (CALLS.md, *Clipping a call*).
///
/// The order is [ClipRecorder]'s: the flag goes round before anything is
/// kept. The notices are [ClipNoticeRules]': once per person per call that
/// they have clipping on, at most once a minute that they clipped.
mixin _ClippingMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  ClipRecorder get _clipRecorder;
  ClipNoticeRules get _clipRules;
  ClipLibrary get _clipLibrary;
  VaultCubit get _vaultCubit;
  SessionRepository? get _session;
  VoiceApi? _voiceOn(String serverId);

  Future<bool> _publishSelfStateChecked();

  /// Brings the ring and the flag in line with the settings and the call.
  /// Run after a state change has landed, never from inside [onChange].
  void _syncClipping() {
    if (isClosed) return;
    final app = _appCubit.state;
    unawaited(
      _clipRecorder.update(
        enabled: app.clippingEnabled,
        connected:
            state.connectionState == LiveKitConnectionState.connected &&
            state.room?.localParticipant != null,
        inCall: state.inCall,
        call: state.callKey,
        seconds: app.clipSeconds,
        includeMic: app.clipIncludeMic,
      ),
    );
  }

  /// [ClipRecorder]'s publish: this client's attributes, the flag in them
  /// read from [ClipRecorder.claiming] (which is [clipping] by now),
  /// answering whether the call has them.
  Future<bool> _publishClipping(bool clipping) => _publishSelfStateChecked();

  /// Tells the call's people about anybody with clipping on they have not
  /// been told about yet in this call: on joining, and as each arrives or
  /// turns it on.
  // Its callers are in `_RoomEventsMixin` and `_LiveKitConnectionMixin`,
  // where the call resolves to their abstract declarations — which the
  // unused-element check can't follow.
  // ignore: unused_element
  void _noticeClippers() {
    final room = state.room;
    if (room == null || isClosed) return;
    final self = room.localParticipant;
    final selfId = self == null
        ? ''
        : ParticipantIdentity.userIdOf(self.identity);
    final names = <String, String>{};
    for (final p in room.remoteParticipants.values) {
      if (ParticipantIdentity.isWatch(p.identity) ||
          ParticipantIdentity.isShare(p.identity)) {
        continue;
      }
      if (!VoiceAttributes.isClipping(p.attributes)) continue;
      names.putIfAbsent(
        ParticipantIdentity.userIdOf(p.identity),
        () => _clipNameOf(p),
      );
    }
    final fresh = _clipRules.newlyClipping(names.keys, selfId: selfId);
    if (fresh.isEmpty) return;
    emit(
      state.copyWith(
        notice: Notice.info(
          'Clipping',
          clippingOnText([for (final id in fresh) names[id]!]),
        ),
      ),
    );
  }

  /// The server says the person on connection [identity] clipped the last
  /// [seconds] of the call ([ClipSignal]). Named from the room, so a notice
  /// is about somebody this client can see in the call.
  // See [_noticeClippers].
  // ignore: unused_element
  void _hearClip(String identity, int seconds) {
    final room = state.room;
    if (isClosed || room == null) return;
    final self = room.localParticipant;
    final userId = ParticipantIdentity.userIdOf(identity);
    if (self != null && ParticipantIdentity.userIdOf(self.identity) == userId) {
      return;
    }
    final from = room.remoteParticipants[identity];
    if (from == null) return;
    if (!_clipRules.admitClip(userId, DateTime.now())) return;
    emit(
      state.copyWith(
        notice: Notice.info('Clipped', clippedText(_clipNameOf(from), seconds)),
      ),
    );
  }

  /// Has the server tell the call about a clip (`note_clip`). The call is
  /// read now, before anything is awaited, so a clip is told to the call it
  /// was made in. A server before console 1.9.0 has no `note_clip`, and the
  /// others are not told there.
  Future<void> _tellCall(int seconds) async {
    final serverId = state.callServerId;
    final dm = state.dmCall;
    final channelId = state.currentChannelId;
    final voice = serverId == null ? null : _voiceOn(serverId);
    if (voice == null || (dm == null && channelId == null)) return;
    final response = await voice.noteClip(
      channelId: dm == null ? channelId : null,
      callId: dm?.callId,
      seconds: seconds,
    );
    if (!response.success) {
      HelperMethods.printDebug(
        '[Clips] could not tell the call: ${response.errorCode}',
      );
    }
  }

  static final int _clippedNotificationId = stableNotificationId('clipped');

  String _clipNameOf(Participant p) =>
      p.name.trim().isNotEmpty ? p.name.trim() : 'Someone';

  /// The clip shortcut: keeps what the ring holds, tells the call, and queues
  /// it for the trim view. Says why when there is nothing to keep.
  Future<void> clipCall() async {
    if (!state.inCall) {
      _clipNotice('Nothing to clip', 'Join a call first.');
      return;
    }
    if (!_clipRecorder.available) {
      _clipNotice('Clipping', 'Clips are made on Windows and Linux.');
      return;
    }
    if (!_appCubit.state.clippingEnabled) {
      _clipNotice('Clipping is off', 'Turn it on in Settings, under Clips.');
      return;
    }
    final audio = _clipRecorder.snapshot();
    if (audio == null || audio.frames == 0) {
      _clipNotice('Nothing to clip yet', 'The call has not played anything.');
      return;
    }
    // Kept before anything else is awaited, while the call is still the one
    // it was clipped from.
    unawaited(_keepClip(audio));
    unawaited(_tellCall(audio.seconds.clamp(1, ClipSignal.maxSeconds)));
    // Rift may be behind a game: the sound says the press was heard, and
    // the system's notification what was kept, since the trim view waits
    // for Rift to be seen. One notification, each press replacing the last.
    unawaited(SoundService.instance.play(AppSound.clip));
    if (!WindowFocusService.instance.isFocused) {
      unawaited(
        NotificationService.instance.showMessage(
          id: _clippedNotificationId,
          title: 'Clipped',
          body: clippedBackgroundText(audio.seconds),
          chime: false,
        ),
      );
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        pendingClips: ClipRecorder.enqueue(state.pendingClips, audio),
      ),
    );
  }

  /// Puts [audio] among the clips this device keeps, so closing the trim
  /// view unsaved loses nothing (`ClipLibrary`). Named by where it was taken,
  /// as it was then.
  Future<void> _keepClip(CallClipAudio audio) async {
    final seed = _vaultCubit.state.masterSeed;
    if (seed == null) return;
    final dm = state.dmCall;
    final serverId = state.callServerId;
    final server = serverId == null ? null : _session?.serverById(serverId);
    final channelId = dm == null ? state.currentChannelId : null;
    String? channelName;
    for (final channel in server?.channels ?? const <Channel>[]) {
      if (channel.id == channelId) channelName = channel.name;
    }
    final place = dm != null
        ? 'Call with ${dm.peerName}'
        : [?channelName, ?server?.name].join(' · ');
    try {
      await _clipLibrary.add(
        seed,
        audio,
        serverId: serverId,
        channelId: channelId,
        place: place.isEmpty ? 'A call' : place,
        fromDmCall: dm != null,
      );
    } catch (e) {
      HelperMethods.printDebug('[Clips] could not keep the clip: $e');
    }
  }

  /// The trim view has taken clip [id].
  void takeClip(int id) {
    if (isClosed) return;
    emit(
      state.copyWith(
        pendingClips: [
          for (final clip in state.pendingClips)
            if (clip.id != id) clip,
        ],
      ),
    );
  }

  void _clipNotice(String title, String message) {
    if (isClosed) return;
    emit(state.copyWith(notice: Notice.info(title, message)));
  }
}
