part of 'channel_chat_cubit.dart';

/// Phase-2 key distribution: one sweep pass performs every wrap the local
/// user can do — bootstrapping version-0 channels, healing members who lack a
/// current-version entry or an older one (their scrollback), and rotating a
/// channel whose key was sealed to somebody since banned. Runs on server-ready and whenever the key-sweep
/// doorbell rings (a member published a new chat key, or another client just
/// healed someone).
mixin _ChatSweepMixin on Cubit<ChannelChatState> {
  SessionRepository get _session;
  CryptoRepository get _crypto;
  Future<ChatIdentity?> _chatIdentity(Server server);

  /// The server chat is set up on — see `_ChatReadyMixin`.
  Server? get _readyServer;
  void _ringKeySweepDoorbell({Iterable<String>? channels});

  /// Implemented by [_ChatReadyMixin]: what this client does on hearing
  /// that keys moved.
  void _followNewKeys();

  bool _sweeping = false;

  /// Rung while a sweep was running. The work it announces may have come
  /// after that sweep's last read, so one more pass runs once it ends;
  /// dropped, it waited for the next ring.
  bool _sweepAgain = false;

  /// A pass seals at most 500 entries, so this covers a key change in a
  /// channel of 100,000 members; anything left over goes to the next ring.
  static const _maxSweepPasses = 200;

  Future<void> _runKeySweep() async {
    if (_sweeping) {
      _sweepAgain = true;
      return;
    }
    _sweeping = true;
    _sweepAgain = false;
    try {
      final server = _readyServer;
      if (server == null) return;
      final identity = await _chatIdentity(server);
      if (identity == null) return;

      final healed = <String>{};
      // The server hands out work 500 entries at a time and says `more` when
      // it held some back: the rest of a big channel's new key, or old
      // versions. A pass that stored nothing ends it, so a batch that keeps
      // failing is not asked for forever.
      for (var pass = 0; pass < _maxSweepPasses; pass++) {
        // The server the sweep started on, throughout: the identity above is
        // that server's, and the server shown can move while a pass runs.
        final response = await ChannelKeysApi(
          _session.on(server.id),
        ).sweepChannelKeys();
        if (!response.success) break;
        final data = response.data as Map<String, dynamic>;
        final work = (data['work'] as List).cast<Map<String, dynamic>>();

        // Every job sealed first, then the pass sent in one request: one
        // a channel kept a newcomer's last channel locked until the server
        // had answered for each before it.
        final batches = <SealedKeys>[];
        for (final job in work) {
          try {
            final sealed = await _sealSweepJob(job, identity);
            if (sealed != null) batches.add(sealed);
          } catch (e) {
            HelperMethods.printDebug('[Chat] sweep job failed: $e');
          }
        }
        final stored = batches.isEmpty
            ? const <String>{}
            : await _storeSweep(batches, server.id);
        healed.addAll(stored);
        if (data['more'] != true || stored.isEmpty) break;
      }
      // Wake waiting members so they refetch their (now healed) keyring —
      // the channels named, so the apps showing others need not read. And
      // this client too: a ring is not echoed to the cubit that rang it,
      // so the one that minted a rotation kept sealing the open channel
      // under the version before it — readable to whoever the rotation was
      // for keeping out, and locked to whoever it let in (found in review,
      // Nov 21).
      if (healed.isNotEmpty) {
        _ringKeySweepDoorbell(channels: healed);
        _followNewKeys();
      }
    } finally {
      _sweeping = false;
    }
    if (_sweepAgain && !isClosed) unawaited(_runKeySweep());
  }

  /// One unit of sweep work, sealed and ready to store: null when there is
  /// nobody to seal for.
  Future<SealedKeys?> _sealSweepJob(
    Map<String, dynamic> job,
    ChatIdentity identity,
  ) async {
    final channelId = job['channel_id'] as String;
    final version = job['key_version'] as int;
    final missing = (job['members_missing'] as List)
        .cast<Map<String, dynamic>>();
    if (missing.isEmpty) return null;

    // Bootstrapping an empty channel and rotating a compromised one are the
    // same act — mint a key nobody has yet and seal it to the people entitled
    // to it. Only the version differs, and both are one past what is there.
    final rotate = job['rotate'] == true;

    final Uint8List channelKey;
    final int postVersion;
    if (version == 0 || rotate) {
      channelKey = _crypto.generateChannelKey();
      postVersion = version + 1;
    } else {
      channelKey = await _crypto.unwrapKey(
        wrapped: WrappedKey.fromJson(job['my_key'] as Map<String, dynamic>),
        myKeyPair: identity.keyPair,
      );
      postVersion = version;
    }

    final entries = await _crypto.sealKeyringEntries(
      key: channelKey,
      members: missing,
    );

    return SealedKeys(
      channelId: channelId,
      keyVersion: postVersion,
      entries: entries,
      mint: version == 0 || rotate,
      link: rotate && job['link'] == true
          ? await _linkBack(job, identity, channelId, channelKey, postVersion)
          : null,
    );
  }

  /// Stores a sealed pass on [serverId]. The channels any of it was stored
  /// in, empty when none was.
  Future<Set<String>> _storeSweep(
    List<SealedKeys> batches,
    String serverId,
  ) async {
    final response = await ChannelKeysApi(
      _session.on(serverId),
    ).storeKeyWork(batches);
    if (!response.success) {
      HelperMethods.printDebug(
        '[Chat] sweep store failed: ${response.errorCode}',
      );
      return const {};
    }
    final results = ((response.data as Map<String, dynamic>)['results'] as List)
        .cast<Map<String, dynamic>>();
    final stored = <String>{};
    for (var i = 0; i < results.length && i < batches.length; i++) {
      final result = results[i];
      if (result['success'] == true) {
        stored.add(batches[i].channelId);
      } else if (result['code'] != ErrorCode.keyringConflict) {
        // A conflict just means another client won the same race — fine.
        HelperMethods.printDebug('[Chat] sweep job refused: ${result['code']}');
      }
    }
    return stored;
  }

  /// The outgoing key sealed under the one this rotation mints, so whoever is
  /// sealed the new one can open the old (ARCHITECTURE.md §4, *The key chain*).
  /// The server asks for one only where nothing before the rotation is being
  /// kept from the people after it. Null when it cannot be made: the
  /// rotation goes ahead without it, and its members keep a row for the old
  /// version instead.
  Future<({String ciphertext, String nonce})?> _linkBack(
    Map<String, dynamic> job,
    ChatIdentity identity,
    String channelId,
    Uint8List newKey,
    int newVersion,
  ) async {
    final mine = job['my_key'] as Map<String, dynamic>?;
    if (mine == null) return null;
    try {
      final oldKey = await _crypto.unwrapKey(
        wrapped: WrappedKey.fromJson(mine),
        myKeyPair: identity.keyPair,
      );
      return await _crypto.sealKeyLink(
        newerKey: newKey,
        olderKey: oldKey,
        channelId: channelId,
        newerVersion: newVersion,
      );
    } catch (e) {
      HelperMethods.printDebug('[Chat] key link failed: $e');
      return null;
    }
  }
}
