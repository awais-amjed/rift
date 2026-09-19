part of 'livekit_cubit.dart';

/// End-to-end encryption for a call (ARCHITECTURE.md §5).
///
/// Media used to be DTLS-SRTP only: encrypted to the server and readable by it,
/// which is how every SFU works and was the one place in Rift where the server
/// could see what members said to each other. Frames are now encrypted with the
/// channel's own key — the same key the text keyring already distributes,
/// sealed per member, and never sent anywhere.
///
/// **Per-participant key mode, not shared-key.** LiveKit offers a simpler mode
/// where one key encrypts the whole room, and it would put BOTS.md §2 in the
/// middle of a call: a bot must encrypt to be heard, holding the key *is* read
/// access, and a music bot would arrive able to hear every word. Instead every
/// participant is registered with the key their frames use — members with the
/// channel key, a bot with [VoiceKeys.forBot], which members can derive and the
/// bot cannot invert. See `voice_keys.dart`.
///
/// A key has to be registered for a participant before their frames can be
/// decrypted, and participants arrive at any time, so this runs on connect for
/// whoever is already in the room and again whenever somebody joins.
mixin _E2EEMixin on Cubit<LiveKitState> {
  CryptoRepository get _crypto;
  VaultCubit get _vaultCubit;
  ServerCubit? get _serverCubit;

  /// Whether a user id belongs to a bot, so its frames are keyed differently.
  ///
  /// Set from outside rather than injected: the member roster is built after
  /// this cubit and would otherwise be a construction cycle. Null answers "not
  /// a bot", which is the safe default — a member keyed as a member is readable
  /// by the room, where a member keyed as a bot would be audible to nobody.
  bool Function(String userId)? _isBotResolver;

  /// Public because it is set from outside the cubit; cubit-internal otherwise
  /// (CODE_STYLE §5).
  set isBotResolver(bool Function(String userId)? resolver) =>
      _isBotResolver = resolver;

  /// The keys for the channel being joined.
  ///
  /// Lives here rather than on the cubit class because this mixin is its only
  /// reader, and lazily because there is nothing to build one from until a
  /// server is selected. Its own ring rather than the chat cubit's: a call and
  /// an open text channel are different channels most of the time, and the two
  /// must not clear each other's keys when either is left.
  ChannelKeyring? _keyringOrNull;

  ChannelKeyring? get _keyring {
    final server = _serverCubit;
    if (server == null) return null;
    return _keyringOrNull ??= ChannelKeyring(
      serverCubit: server,
      vaultCubit: _vaultCubit,
      crypto: _crypto,
    );
  }

  /// The key ring in force for the call being set up, and the LiveKit slot it
  /// occupies. Held between `connect` and the participant events that follow.
  BaseKeyProvider? _keyProvider;
  Uint8List? _callChannelKey;
  int _callKeyIndex = 0;

  /// The key-sweep doorbell, held only for the duration of a call.
  ///
  /// A rotation matters to a call that is happening and to nothing else, so
  /// this is one extra Realtime channel held for minutes rather than for the
  /// session. `ChannelChatCubit` keeps its own for the open text channel: a
  /// call and an open channel are different channels most of the time.
  final KeySweepDoorbell _rotations = KeySweepDoorbell();

  /// Bots an admin has allowed to hear this channel. They are keyed with the
  /// channel key itself rather than a derived one — there is no third thing to
  /// give a listener, which is why that grant is a key grant and cannot be
  /// taken back (BOTS.md §6, §6b).
  Set<String> _callListeningBots = const {};

  /// Load the channel's key and build the options `room.connect` takes.
  ///
  /// Returns null when there is no key to be had — a locked vault, or a channel
  /// nobody has sealed a key to us for yet. **The caller must refuse to
  /// connect** rather than falling back to an unencrypted room: joining
  /// unencrypted would work, sound fine, and be the exact property this is here
  /// to provide. A call you cannot join is a bug; a call that is quietly
  /// readable is a broken promise.
  Future<E2EEOptions?> _prepareE2EE(String channelId) async {
    final keyring = _keyring;
    if (keyring == null) return null;

    var outcome = await keyring.loadOrBootstrap(channelId);

    // Nobody has sealed this channel's key to us yet, which is the ordinary
    // state of a member joining their first call. Somebody online can seal it,
    // and the key-sweep doorbell is how they are told to — which is exactly
    // what the text path does when it opens a channel it has no key for.
    //
    // Voice used to only refuse. So a member whose first stop was a call sat on
    // "waiting for this channel's key" until another member happened to open
    // that channel by hand, and the "Try again" button could not help, because
    // trying again rang nothing either.
    final server = _serverCubit?.state.selectedServer;
    if (outcome.isWaiting && server != null) {
      // Subscribing before ringing: an unsubscribed doorbell has no client to
      // ring with, and the heal being asked for is announced on the same topic.
      _watchKeyRotations(server, channelId);
      _rotations.ring();
      outcome = await _awaitHeal(keyring, channelId);
    }

    final key = keyring.currentKey;
    if (!outcome.isReady || key == null) {
      HelperMethods.printDebug(
        '[LiveKit] no channel key for $channelId — refusing to join',
      );
      // Nothing is connecting, so nothing should be left holding a
      // subscription — the connect path is what hands this one over to the
      // call, and it is not being reached.
      unawaited(_rotations.stop());
      return null;
    }

    _callChannelKey = key;
    _callKeyIndex = VoiceKeys.keyIndex(keyring.currentVersion);
    _callListeningBots =
        await _serverCubit?.voiceListenerIds(channelId) ?? const {};

    // `sharedKey: false` is the whole point — see the class comment.
    final provider = await BaseKeyProvider.create(sharedKey: false);
    _keyProvider = provider;
    return E2EEOptions(keyProvider: provider);
  }

  /// How long to wait for another member's client to seal us in.
  ///
  /// The budget the text path allows for the same exchange — a ring, a sweep on
  /// somebody else's device, and a round trip back. Long enough for that to
  /// land on a normal connection, short enough that a channel nobody can heal
  /// says so rather than spinning.
  static const _healGrace = Duration(seconds: 4);
  static const _healPoll = Duration(milliseconds: 700);

  /// Re-ask for the keyring until somebody seals us in, or the grace runs out.
  ///
  /// Polled rather than driven by the doorbell it just rang. The ring that
  /// announces a heal is the same ring that announces a rotation, and this
  /// client is not in a call yet — so driving it from [_onKeyDoorbell] would
  /// give that handler a second meaning and a second lifetime to get right. A
  /// handful of requests over four seconds is the cheaper of the two.
  Future<KeyringOutcome> _awaitHeal(
    ChannelKeyring keyring,
    String channelId,
  ) async {
    final deadline = DateTime.now().add(_healGrace);
    var outcome = const KeyringOutcome.waiting();
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_healPoll);
      if (isClosed) break;
      outcome = await keyring.loadOrBootstrap(channelId);
      if (!outcome.isWaiting) return outcome;
    }
    return outcome;
  }

  /// The key the current call is encrypted with, and its ring slot.
  ///
  /// Read by the screen-share path, which opens a *second* connection into the
  /// same room from Rust and has to encrypt with the same key. Publishing that
  /// one in the clear would not fail loudly — LiveKit skips the frame cryptor
  /// for a track that declares no encryption — it would just hand the server
  /// the one stream nobody meant it to have.
  ({Uint8List key, int index})? get callEncryption {
    final key = _callChannelKey;
    return key == null ? null : (key: key, index: _callKeyIndex);
  }

  /// Listen for rotations for as long as [channelId]'s call lasts.
  void _watchKeyRotations(Server server, String channelId) {
    final realtime = _serverCubit?.realtime;
    if (realtime == null) return;
    _rotations.listen(
      realtime,
      server,
      () => unawaited(_onKeyDoorbell(channelId)),
    );
  }

  void _clearE2EE() {
    unawaited(_rotations.stop());
    _keyProvider = null;
    _callChannelKey = null;
    _callKeyIndex = 0;
    _callListeningBots = const {};
  }

  /// Register the key for one participant, by their LiveKit identity.
  ///
  /// A screen share is a second connection held by the same person and carries
  /// the same key: its identity has a suffix, and the frame cryptor is keyed by
  /// the identity string, so it needs its own registration rather than being
  /// folded into the person's.
  /// Where a bot's media key goes in the ring — see [_registerParticipantKey].
  static const int _botKeyIndex = 0;

  Future<void> _registerParticipantKey(String identity) async {
    final provider = _keyProvider;
    final channelKey = _callChannelKey;
    if (provider == null || channelKey == null) return;

    final userId = ParticipantIdentity.userIdOf(identity);
    if (userId.isEmpty) return;

    // Three cases, and only the middle one is interesting. A member uses the
    // channel key. A bot allowed to hear uses it too, because a listener needs
    // the real thing. A bot that may only speak uses a key derived from it,
    // which we can compute and it cannot invert.
    final isBot = _isBotResolver?.call(userId) ?? false;
    final key = !isBot || _callListeningBots.contains(userId)
        ? channelKey
        : await VoiceKeys.forBot(
            crypto: _crypto,
            channelKey: channelKey,
            botId: userId,
          );

    try {
      await provider.setRawKey(
        key,
        participantId: identity,
        // A bot's frames always arrive stamped slot 0, whatever version its key
        // is. Not a choice either side made: `@livekit/rtc-node` cannot move a
        // frame cryptor's index — the FFI request it builds omits a `track_sid`
        // the native side requires and throws — so the cryptor keeps the index
        // it was born with, which is 0. Registering the bot's key at the
        // version's slot instead left every member reporting
        // `FrameCryptorStateMissingKey` on a bot that was publishing perfectly
        // well, with nothing on the bot's side to say so.
        //
        // It costs nothing here. The slot is only ever an agreement about where
        // to look, and the key at it is still per-bot and per-version. What it
        // does cost is a rotation: slot 0 is overwritten rather than added
        // beside, so frames still in flight under the old bot key are lost —
        // the same beat of silence BOTS.md already records for a bot caught by
        // one.
        keyIndex: isBot ? _botKeyIndex : _callKeyIndex,
      );
    } catch (e) {
      // A key that fails to register costs one participant's audio, not the
      // call: everyone else stays readable, and the failure is visible as one
      // person nobody can hear rather than a room that silently drops.
      HelperMethods.printDebug(
        '[LiveKit] key register failed for $identity: $e',
      );
    }
  }

  /// Pick up a key version minted while the call is running, and move the
  /// whole room onto it.
  ///
  /// A channel key rotates when somebody is banned or removed, and that can
  /// happen mid-call. Without this the ring keeps the version it joined on:
  /// everybody stays connected, every track keeps publishing, and the audio
  /// stops arriving — the failure with no error in it anywhere.
  ///
  /// The old key is left in its slot rather than cleared. LiveKit's ring holds
  /// sixteen, the two versions occupy different ones, and frames already in
  /// flight were encrypted under the old index.
  /// The doorbell rang while we are in a call.
  ///
  /// Two different things ring it and only one of them is a rotation. A summon
  /// puts a bot on `bots_missing` without changing the key version at all, and
  /// [_absorbKeyRotation] returns early when the version has not moved — so
  /// sealing has to be asked for separately rather than ridden along with it.
  Future<void> _onKeyDoorbell(String channelId) async {
    await _absorbKeyRotation(channelId);
    // After, not before: a rotation changes which version a bot should be
    // sealed under, and sealing first would hand it the one being left behind.
    unawaited(_keyring?.sealMissingBotKeys(channelId) ?? Future.value());
  }

  Future<void> _absorbKeyRotation(String channelId) async {
    final keyring = _keyring;
    final room = state.room;
    if (keyring == null || room == null) return;

    final before = keyring.currentVersion;
    await keyring.absorbNewVersions(channelId);
    final after = keyring.currentVersion;
    if (after == before) return;

    final key = keyring.currentKey;
    if (key == null) return;

    _callChannelKey = key;
    _callKeyIndex = VoiceKeys.keyIndex(after);
    // A grant can have changed in the same breath as the rotation — revoking
    // one is what rotates the key — so which bot gets which kind is re-read
    // rather than carried over.
    _callListeningBots =
        await _serverCubit?.voiceListenerIds(channelId) ?? const {};

    await _registerAllParticipantKeys(room);
    // Registering the keys is half of it: the frame cryptors were told an index
    // when their tracks were published and keep using it until they are told
    // another.
    await room.e2eeManager?.setKeyIndex(_callKeyIndex);
    HelperMethods.printDebug(
      '[LiveKit] moved the call from key v$before to v$after',
    );
  }

  /// Register a key for somebody whose track just arrived, and point their
  /// frame cryptor at the right slot.
  ///
  /// The cryptor is created by LiveKit's own `TrackSubscribed` listener, which
  /// reads the key index *at that moment* — and the order of two listeners on
  /// one event is not something to rely on. So the index is set again here
  /// rather than assumed: setting it twice costs nothing, and getting it once
  /// too late is a participant nobody can hear.
  Future<void> _registerSubscribedKey(String identity) async {
    await _registerParticipantKey(identity);
    try {
      await state.room?.e2eeManager?.setKeyIndex(
        _callKeyIndex,
        participantIdentity: identity,
      );
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] key index for $identity: $e');
    }
  }

  /// Everyone already in the room when we arrive, plus ourselves.
  ///
  /// All at once. This is awaited before the call reports itself connected —
  /// it has to be, or the first frames from somebody already here arrive with
  /// no key to read them by — so its cost is join latency the member watches.
  /// One registration is a hop into the native frame cryptor, and doing them
  /// in series meant a call of a hundred people took a hundred of those
  /// before the room appeared. They are independent: each names a different
  /// participant, and none reads what another wrote.
  Future<void> _registerAllParticipantKeys(Room room) async {
    final local = room.localParticipant?.identity;
    await Future.wait([
      if (local != null) _registerParticipantKey(local),
      for (final remote in room.remoteParticipants.values)
        _registerParticipantKey(remote.identity),
    ]);
  }
}
