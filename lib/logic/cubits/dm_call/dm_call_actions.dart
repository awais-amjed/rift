part of 'dm_call_cubit.dart';

/// Over the cubit-part budget and one job: the four moves a DM call makes,
/// which share its begin and drop steps.
///
/// Placing, answering, refusing and ending a call — each an RPC first, and
/// the room second, because the row is what decides whether there is a call
/// to be in.
mixin _DmCallActionsMixin on Cubit<DmCallState> {
  DmCallsApi _callsOn(Server server);
  LiveKitCubit get _livekit;
  VaultCubit get _vault;
  AppCubit get _app;
  CryptoRepository get _crypto;
  Server? _server(String serverId);
  void _ask(String serverId);
  void _syncSounds();
  void _syncTimers();
  void _watchPeer(ActiveDmCall active, LiveKitState lk);

  /// The call whose room this device asked LiveKit to join. Set only once the
  /// join has been asked for, so a LiveKit state without it can be read as
  /// "left from somewhere else" — the leave button, or a voice channel.
  String? _joinedCallId;

  /// Calls this device has answered, refused or hung up. A `my_dm_calls`
  /// answer fetched just before the press and landing just after it still
  /// says they ring, and folded in as it came it put a declined ring back on
  /// screen (review, Nov 22).
  final Set<String> _settled = {};

  /// Ring [peerId] on [serverId], the server the conversation or profile it
  /// was pressed from is about.
  ///
  /// Already in a call with them is a no-op; in a call with somebody else
  /// ends that one first, as picking a voice channel does.
  Future<void> startCall({
    required String serverId,
    required String peerId,
    required String peerName,
  }) async {
    final server = _server(serverId);
    if (server == null || state.busy) return;
    if (state.isWith(server.id, peerId)) return;
    // Held before the hang-up, not after: the call before this one takes
    // half a second to leave, and a second press in it began this twice.
    emit(state.copyWith(busy: true));
    if (state.active != null) await hangUp();

    final response = await _callsOn(server).startDmCall(peerId);
    emit(state.copyWith(busy: false));
    if (!response.success) {
      emit(
        state.copyWith(
          notice: Notice.error(
            CallRefusal.describe(response.errorCode, peerName: peerName) ??
                response.error ??
                'Couldn\'t start the call.',
          ),
        ),
      );
      return;
    }
    final call = DmCall.fromJson(response.data as Map<String, dynamic>);
    await _begin(server, call);
  }

  /// Pick up [incoming]. Answers whether this device is now in the call —
  /// false when another device got there first or it had already ended,
  /// which has been said by the time this returns.
  Future<bool> answer(IncomingDmCall incoming) async {
    final server = _server(incoming.serverId);
    if (server == null || state.busy) return false;
    if (_keyHeld(incoming.call)) return false;
    emit(state.copyWith(busy: true));
    if (state.active != null) await hangUp();

    // A phone woken by the push may be showing this call in the shade too.
    unawaited(NotificationService.instance.cancelCall(incoming.call.id));
    _settled.add(incoming.call.id);
    final response = await _callsOn(server).answerDmCall(incoming.call.id);
    emit(
      state.copyWith(
        busy: false,
        incoming: [
          for (final entry in state.incoming)
            if (entry.call.id != incoming.call.id) entry,
        ],
      ),
    );
    _syncSounds();
    if (!response.success) {
      // Not answered: if it still rings, the next answer from the server may
      // offer it again. One answered elsewhere or over is not listed ringing.
      _settled.remove(incoming.call.id);
      emit(
        state.copyWith(
          notice: Notice.error(
            CallRefusal.describe(
                  response.errorCode,
                  peerName: incoming.call.peerName,
                ) ??
                response.error ??
                'Couldn\'t answer the call.',
          ),
        ),
      );
      return false;
    }
    final call = DmCall.fromJson(response.data as Map<String, dynamic>);
    await _begin(server, call);
    return true;
  }

  /// Answer [callId] on [serverId] from its notification: the app has just
  /// been opened by the press, and knows the call only by its id. Asked for
  /// first, because a ring can end in the moment it takes to open the app.
  ///
  /// Waits for the vault if it is still locked — a call's key is derived
  /// from it, and a phone opened from its lock screen may not have it yet.
  Future<bool> answerById(String serverId, String callId) async {
    final server = _server(serverId);
    if (server == null) return false;
    if (_vault.state.masterSeed == null) {
      await _vault.stream
          .firstWhere((v) => v.masterSeed != null)
          .timeout(const Duration(minutes: 1), onTimeout: () => _vault.state);
    }
    final response = await _callsOn(server).myDmCalls(known: [callId]);
    // Not asked is not over: a phone just opened from the shade may not be
    // online yet, and "already ended" took down a call still ringing.
    if (!response.success) {
      emit(
        state.copyWith(
          notice: Notice.error(
            response.error ?? 'Couldn\'t reach the server to answer.',
          ),
        ),
      );
      return false;
    }
    final call = DmCall.listFrom(
      response.data,
    ).where((c) => c.id == callId).firstOrNull;
    if (call == null || !call.isRinging) {
      unawaited(NotificationService.instance.cancelCall(callId));
      emit(
        state.copyWith(notice: Notice.error('That call has already ended.')),
      );
      return false;
    }
    return answer(
      IncomingDmCall(
        serverId: server.id,
        serverName: server.name,
        call: call,
        seenAt: DateTime.now(),
      ),
    );
  }

  /// Decline [callId] from its notification, with the app running.
  Future<void> declineById(String serverId, String callId) async {
    unawaited(NotificationService.instance.cancelCall(callId));
    final server = _server(serverId);
    if (server == null) return;
    emit(
      state.copyWith(
        incoming: [
          for (final entry in state.incoming)
            if (entry.call.id != callId) entry,
        ],
      ),
    );
    _settled.add(callId);
    _syncSounds();
    await _callsOn(server).endDmRing(callId);
  }

  /// Refuse [incoming]. Recorded as declined, which the caller is told.
  Future<void> decline(IncomingDmCall incoming) async {
    unawaited(NotificationService.instance.cancelCall(incoming.call.id));
    emit(
      state.copyWith(
        incoming: [
          for (final entry in state.incoming)
            if (entry.call.id != incoming.call.id) entry,
        ],
      ),
    );
    _settled.add(incoming.call.id);
    _syncSounds();
    final server = _server(incoming.serverId);
    if (server == null) return;
    // Only while it rings: a decline pressed here a moment after another of
    // our devices answered must not end the call that one is in.
    await _callsOn(server).endDmRing(incoming.call.id);
  }

  /// End the call this device is in, from our end. Also what quitting does
  /// ([BeforeQuit]), so the other end is not left talking to nobody.
  Future<void> hangUp() async {
    final active = state.active;
    if (active == null) return;
    _settled.add(active.call.id);
    try {
      await _dropActive(hangUpRoom: true);
    } finally {
      // Told even when leaving the room threw — stopping a share on the way
      // out, say — or the other end waits out its grace in a dead call.
      final server = _server(active.serverId);
      if (server != null) {
        await _callsOn(server).endDmCall(active.call.id);
      }
    }
  }

  /// Our ring has gone unanswered for [DmCall.ringFor]. Given up on only if
  /// it still rings: an answer that landed in the last moment — its doorbell
  /// still on the way, or lost — is a call to stay in, not one to end.
  Future<void> _giveUpRinging(String callId) async {
    final active = state.active;
    if (active == null || active.call.id != callId) return;
    final server = _server(active.serverId);
    final response = server == null
        ? null
        : await _callsOn(server).endDmRing(callId);
    if (state.active?.call.id != callId) return;
    final data = response?.data;
    if (response != null && response.success && data is Map<String, dynamic>) {
      // Answered after all, or ended — [_onActiveRow] says which, and names
      // a ring that went unanswered.
      await _onActiveRow(DmCall.fromJson(data));
      return;
    }
    _settled.add(callId);
    await _dropActive(hangUpRoom: true);
    emit(
      state.copyWith(
        notice: Notice.info(
          'Call ended',
          '${active.call.peerName} didn\'t answer.',
        ),
      ),
    );
  }

  /// Whether [call] is held because the other person's key changed since
  /// it was verified — said, when it is.
  ///
  /// A call's media key is derived from the key in the call's row, which the
  /// server hands over. Used without the checks a DM's sending makes, a
  /// server that swapped it for calls alone could listen in, and nothing
  /// said so even for a contact whose safety code was compared (review,
  /// Nov 22). So it is noted as theirs, as opening the conversation would —
  /// which puts the change in front of the person there — and a verified
  /// contact's changed key stops the call, as it stops sending.
  bool _keyHeld(DmCall call) {
    final key = call.peerChatPublicKey;
    if (key == null || key.isEmpty) return false;
    final person = 'server:${call.peerId}';
    _app.noteChatKey(person, key);
    if (!_app.state.keyChangedSinceVerified(person)) return false;
    emit(
      state.copyWith(
        notice: Notice.error(
          '${call.peerName}\'s key has changed since you verified it. '
          'Compare your safety code again in your messages before calling.',
        ),
      ),
    );
    return true;
  }

  /// This device is now on [call]: hold it, and join its room — the caller
  /// straight away, so the line is open when the other end picks up.
  Future<void> _begin(Server server, DmCall call) async {
    emit(
      state.copyWith(
        active: ActiveDmCall(serverId: server.id, call: call),
      ),
    );
    _syncSounds();
    _syncTimers();

    if (_keyHeld(call)) {
      await hangUp();
      return;
    }
    final key = await _mediaKey(server, call);
    // Hung up while the key was being worked out — and perhaps another call
    // begun, which the hang-up below must not end.
    if (state.active?.call.id != call.id) return;
    if (key == null) {
      emit(
        state.copyWith(
          notice: Notice.error(
            '${call.peerName} hasn\'t set up encrypted chat yet, so you '
            'can\'t call them.',
          ),
        ),
      );
      await hangUp();
      return;
    }

    _joinedCallId = call.id;
    await _livekit.connectToDmCall(
      server: server,
      place: DmCallPlace(
        serverId: server.id,
        callId: call.id,
        peerId: call.peerId,
        peerName: call.peerName,
      ),
      mediaKey: key,
      micEnabled: _app.state.audioEnabled,
      cameraEnabled: _app.state.videoEnabled,
    );
  }

  /// The key both ends encrypt this call's media with: derived from the
  /// pair's DM key, which the server never holds ([VoiceKeys.forDmCall]).
  Future<Uint8List?> _mediaKey(Server server, DmCall call) async {
    final peerKey = call.peerChatPublicKey;
    if (peerKey == null || _vault.state.masterSeed == null) return null;
    try {
      final identity = await _vault.getChatIdentityForHost(
        Uri.parse(server.supabaseUrl).host,
      );
      final dmKey = await _crypto.deriveDmKey(
        myKeyPair: identity.keyPair,
        theirPublicKey: CryptoRepository.fromBase64(peerKey),
      );
      return await VoiceKeys.forDmCall(
        crypto: _crypto,
        dmKey: dmKey,
        callId: call.id,
      );
    } catch (e) {
      HelperMethods.printDebug('[DmCall] no media key: $e');
      return null;
    }
  }

  /// The server's latest word on the call we are in.
  Future<void> _onActiveRow(DmCall call) async {
    final active = state.active;
    if (active == null || active.call.id != call.id) return;
    if (!call.isEnded) {
      // A call only moves forward. An answer fetched before ours committed
      // and landing after it said "ringing" again — stopping the heartbeat
      // and, on the caller, arming the thirty seconds a second time.
      if (active.call.isAnswered && !call.isAnswered) return;
      final next = active.withCall(call);
      emit(state.copyWith(active: next));
      _syncSounds();
      _syncTimers();
      // The row turning live comes with nothing from the room, and a caller
      // alone in it hears no room events either: watched from here, so a
      // callee who answered and never arrived ends the call too.
      if (_joinedCallId == call.id) _watchPeer(next, _livekit.state);
      return;
    }
    _settled.add(call.id);
    await _dropActive(hangUpRoom: true);
    final peer = call.peerName;
    final ours = call.callerId != call.peerId;
    final line = switch (call.outcome) {
      DmCallOutcome.declined when ours => '$peer declined the call.',
      DmCallOutcome.missed when ours => '$peer didn\'t answer.',
      _ => null,
    };
    if (line != null) {
      emit(state.copyWith(notice: Notice.info('Call ended', line)));
    }
  }

  /// Forget the call we are in, and leave its room if we are still in it.
  /// Nothing is said to the server — the caller decides whether this is a
  /// hang-up or the server telling us one happened.
  Future<void> _dropActive({required bool hangUpRoom}) async {
    final active = state.active;
    _joinedCallId = null;
    emit(state.copyWith(clearActive: true));
    // An expanded call is expanded for that call; the next opens as a split.
    _app.setDmCallExpanded(false);
    _syncSounds();
    _syncTimers();
    if (hangUpRoom &&
        active != null &&
        _livekit.state.dmCall?.callId == active.call.id) {
      await _livekit.disconnect();
    }
  }
}
