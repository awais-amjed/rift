part of 'channel_chat_cubit.dart';

/// Phase-2 key distribution: one sweep pass performs every wrap the local
/// user can do — bootstrapping version-0 channels and healing members who
/// lack a current-version entry. Runs on server-ready and whenever the
/// key-sweep doorbell rings (a member published a new chat key, or another
/// client just healed someone).
mixin _ChatSweepMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Future<ChatIdentity?> _chatIdentity(Server server);
  void _ringKeySweepDoorbell();

  bool _sweeping = false;

  Future<void> _runKeySweep() async {
    if (_sweeping) return;
    _sweeping = true;
    try {
      final server = _serverCubit.state.selectedServer;
      if (server == null) return;
      final identity = await _chatIdentity(server);
      if (identity == null) return;

      final response = await _serverCubit.sweepChannelKeys();
      if (!response.success) return;
      final work = ((response.data as Map<String, dynamic>)['work'] as List)
          .cast<Map<String, dynamic>>();
      if (work.isEmpty) return;

      var healedAny = false;
      for (final job in work) {
        try {
          if (await _performSweepJob(job, identity)) healedAny = true;
        } catch (e) {
          HelperMethods.printDebug('[Chat] sweep job failed: $e');
        }
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
    final missing =
        (job['members_missing'] as List).cast<Map<String, dynamic>>();
    if (missing.isEmpty) return false;

    final Uint8List channelKey;
    final int postVersion;
    if (version == 0) {
      // Fresh channel — bootstrap v1.
      channelKey = _crypto.generateChannelKey();
      postVersion = 1;
    } else {
      channelKey = await _crypto.unwrapKey(
        wrapped: WrappedKey.fromJson(job['my_key'] as Map<String, dynamic>),
        myKeyPair: identity.keyPair,
      );
      postVersion = version;
    }

    final entries = <Map<String, dynamic>>[];
    for (final member in missing) {
      final wrapped = await _crypto.wrapKey(
        key: channelKey,
        recipientPublicKey:
            CryptoRepository.fromBase64(member['chat_public_key'] as String),
      );
      entries.add({'user_id': member['user_id'], ...wrapped.toJson()});
    }

    final posted = await _serverCubit.postChannelKeys(
      channelId: channelId,
      keyVersion: postVersion,
      entries: entries,
    );
    // A conflict just means another client won the same race — fine.
    return posted.success;
  }
}
