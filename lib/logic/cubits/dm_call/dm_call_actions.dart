part of 'dm_call_cubit.dart';

/// Placing, answering, refusing and ending a call — each an RPC first, and
/// the room second, because the row is what decides whether there is a call
/// to be in.
mixin _DmCallActionsMixin on Cubit<DmCallState> {
  ServerCubit get _serverCubit;
  LiveKitCubit get _livekit;
  VaultCubit get _vault;
  AppCubit get _app;
  CryptoRepository get _crypto;
  Server? _server(String serverId);
  void _ask(String serverId);
  void _syncSounds();
  void _syncTimers();

  /// The call whose room this device asked LiveKit to join. Set only once the
  /// join has been asked for, so a LiveKit state without it can be read as
  /// "left from somewhere else" — the leave button, or a voice channel.
  String? _joinedCallId;

  /// Ring [peerId] on the selected server.
  ///
  /// Already in a call with them is a no-op; in a call with somebody else
  /// ends that one first, as picking a voice channel does.
  Future<void> startCall({
    required String peerId,
    required String peerName,
  }) async {
    final server = _serverCubit.state.selectedServer;
    if (server == null || state.busy) return;
    if (state.isWith(server.id, peerId)) return;
    if (state.active != null) await hangUp();

    emit(state.copyWith(busy: true));
    final response = await _serverCubit.startDmCall(server, peerId);
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
    if (state.active != null) await hangUp();

    // A phone woken by the push may be showing this call in the shade too.
    unawaited(NotificationService.instance.cancelCall(incoming.call.id));
    emit(state.copyWith(busy: true));
    final response = await _serverCubit.answerDmCall(server, incoming.call.id);
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
    final response = await _serverCubit.myDmCalls(server, known: [callId]);
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
      IncomingDmCall(serverId: server.id, serverName: server.name, call: call),
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
    _syncSounds();
    await _serverCubit.endDmCall(server, callId);
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
    _syncSounds();
    final server = _server(incoming.serverId);
    if (server == null) return;
    await _serverCubit.endDmCall(server, incoming.call.id);
  }

  /// End the call this device is in, from our end. Also what quitting does
  /// ([BeforeQuit]), so the other end is not left talking to nobody.
  Future<void> hangUp() async {
    final active = state.active;
    if (active == null) return;
    await _dropActive(hangUpRoom: true);
    final server = _server(active.serverId);
    if (server != null) {
      await _serverCubit.endDmCall(server, active.call.id);
    }
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
      emit(state.copyWith(active: active.withCall(call)));
      return;
    }
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
