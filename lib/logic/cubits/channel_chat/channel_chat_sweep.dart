part of 'channel_chat_cubit.dart';

/// Phase-2 key distribution: one sweep pass performs every wrap the local
/// user can do — bootstrapping version-0 channels, healing members who lack a
/// current-version entry or an older one (their scrollback), and rotating a
/// channel whose key was sealed to somebody since banned. Runs on server-ready and whenever the key-sweep
/// doorbell rings (a member published a new chat key, or another client just
/// healed someone).
mixin _ChatSweepMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Future<ChatIdentity?> _chatIdentity(Server server);
  void _ringKeySweepDoorbell();

  bool _sweeping = false;

  /// A pass seals at most 500 entries, so this covers a key change in a
  /// channel of 100,000 members; anything left over goes to the next ring.
  static const _maxSweepPasses = 200;

  Future<void> _runKeySweep() async {
    if (_sweeping) return;
    _sweeping = true;
    try {
      final server = _serverCubit.state.selectedServer;
      if (server == null) return;
      final identity = await _chatIdentity(server);
      if (identity == null) return;

      var healedAny = false;
      // The server hands out work 500 entries at a time and says `more` when
      // it held some back: the rest of a big channel's new key, or old
      // versions. A pass that stored nothing ends it, so a batch that keeps
      // failing is not asked for forever.
      for (var pass = 0; pass < _maxSweepPasses; pass++) {
        final response = await _serverCubit.sweepChannelKeys();
        if (!response.success) break;
        final data = response.data as Map<String, dynamic>;
        final work = (data['work'] as List).cast<Map<String, dynamic>>();

        var stored = false;
        for (final job in work) {
          try {
            if (await _performSweepJob(job, identity)) stored = true;
          } catch (e) {
            HelperMethods.printDebug('[Chat] sweep job failed: $e');
          }
        }
        healedAny |= stored;
        if (data['more'] != true || !stored) break;
      }
      // Wake waiting members so they refetch their (now healed) keyring.
      if (healedAny) _ringKeySweepDoorbell();
    } finally {
      _sweeping = false;
    }
  }

  /// Executes one unit of sweep work. Returns true if entries were stored.
  Future<bool> _performSweepJob(
    Map<String, dynamic> job,
    ChatIdentity identity,
  ) async {
    final channelId = job['channel_id'] as String;
    final version = job['key_version'] as int;
    final missing = (job['members_missing'] as List)
        .cast<Map<String, dynamic>>();
    if (missing.isEmpty) return false;

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

    final posted = await _serverCubit.postChannelKeys(
      channelId: channelId,
      keyVersion: postVersion,
      entries: entries,
      mint: version == 0 || rotate,
    );
    // A conflict just means another client won the same race — fine.
    return posted.success;
  }
}
