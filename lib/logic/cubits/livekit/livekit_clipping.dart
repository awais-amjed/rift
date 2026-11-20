part of 'livekit_cubit.dart';

/// Over the cubit-part budget and one job: clipping. Keeping the last stretch
/// of the call for the clip shortcut, and telling the call who does it
/// (CALLS.md, *Clipping a call*).
///
/// The order is [ClipRecorder]'s: the flag goes round before anything is
/// kept. The notices are [ClipNoticeRules]': once per person per call that
/// they have clipping on, at most once a minute that they clipped.
mixin _ClippingMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  ClipRecorder get _clipRecorder;
  ClipNoticeRules get _clipRules;

  /// Whether this client's published attributes say it is clipping.
  bool _clipFlag = false;

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
        seconds: app.clipSeconds,
        includeMic: app.clipIncludeMic,
      ),
    );
  }

  /// [ClipRecorder]'s publish: the flag set to [clipping] in this client's
  /// attributes, answering whether the call has it.
  Future<bool> _publishClipping(bool clipping) {
    _clipFlag = clipping;
    return _publishSelfStateChecked();
  }

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

  /// Somebody else clipped the last [seconds] of the call.
  // See [_noticeClippers].
  // ignore: unused_element
  void _hearClip(Participant from, int seconds) {
    if (isClosed || from is LocalParticipant) return;
    final userId = ParticipantIdentity.userIdOf(from.identity);
    if (!_clipRules.admitClip(userId, DateTime.now())) return;
    emit(
      state.copyWith(
        notice: Notice.info('Clipped', clippedText(_clipNameOf(from), seconds)),
      ),
    );
  }

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
      _clipNotice('Clipping is off', 'Turn it on in Settings, under Voice.');
      return;
    }
    final audio = _clipRecorder.snapshot();
    if (audio == null || audio.frames == 0) {
      _clipNotice('Nothing to clip yet', 'The call has not played anything.');
      return;
    }
    try {
      await state.room?.localParticipant?.publishData(
        ClipSignal.encode(
          seconds: audio.seconds.clamp(1, ClipSignal.maxSeconds),
        ),
        reliable: true,
        topic: ClipSignal.topic,
      );
    } catch (e) {
      HelperMethods.printDebug('[Clips] could not tell the call: $e');
    }
    // Rift may be behind a game: the sound says the press was heard.
    unawaited(SoundService.instance.play(AppSound.stream));
    if (isClosed) return;
    emit(
      state.copyWith(
        pendingClips: ClipRecorder.enqueue(state.pendingClips, audio),
      ),
    );
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
