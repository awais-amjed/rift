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

    final outcome = await keyring.loadOrBootstrap(channelId);
    final key = keyring.currentKey;
    if (!outcome.isReady || key == null) {
      HelperMethods.printDebug(
        '[LiveKit] no channel key for $channelId — refusing to join',
      );
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

  void _clearE2EE() {
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
        keyIndex: _callKeyIndex,
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

  /// Everyone already in the room when we arrive, plus ourselves.
  Future<void> _registerAllParticipantKeys(Room room) async {
    final local = room.localParticipant?.identity;
    if (local != null) await _registerParticipantKey(local);
    for (final remote in room.remoteParticipants.values) {
      await _registerParticipantKey(remote.identity);
    }
  }
}
