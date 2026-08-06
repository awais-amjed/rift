part of 'channel_chat_cubit.dart';

enum _KeyringStatus { ready, waiting, error }

/// How a keyring load ended, and — when it failed — why.
///
/// The reason travels with the outcome rather than being logged and dropped:
/// nearly every failure here is really "the server didn't answer", and the
/// person waiting on the channel deserves to be told that instead of being
/// pointed at the encryption.
class _KeyringResult {
  final _KeyringStatus status;

  /// Set only when [status] is [_KeyringStatus.error].
  final ChatFailure? failure;

  const _KeyringResult.ready() : status = _KeyringStatus.ready, failure = null;

  const _KeyringResult.waiting()
    : status = _KeyringStatus.waiting,
      failure = null;

  const _KeyringResult.failed(ChatFailure this.failure)
    : status = _KeyringStatus.error;

  bool get isReady => status == _KeyringStatus.ready;
  bool get isWaiting => status == _KeyringStatus.waiting;
  bool get isFailed => status == _KeyringStatus.error;
}

/// Keyring handling: publish our chat key, unwrap ours, bootstrap a channel's
/// first key, and heal members missing current-version entries.
mixin _ChatKeyringMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  Set<String> get _publishedChatKey;
  String? get _publishedChatKeySeed;
  void _setPublishedChatKeySeed(String seed);
  void _setCurrentKeyVersion(int version);
  void _ringKeySweepDoorbell();

  /// The chat identity is pinned to v1 for now: the auth key's rotation
  /// version must NOT rotate the chat identity, or every wrapped channel key
  /// would become unreadable. Extending rotation to chat keys is a separate,
  /// designed flow (re-wrap on rotate) — not implicit.
  static const _chatIdentityVersion = 'v1';

  Future<ChatIdentity?> _chatIdentity(Server server) async {
    if (_vaultCubit.state.masterSeed == null) return null;
    final host = Uri.parse(server.supabaseUrl).host;
    return _vaultCubit.getChatIdentityForHost(
      host,
      version: _chatIdentityVersion,
    );
  }

  /// Publish our chat key if not done this run. Returns true when the server
  /// reports the key as newly published (we're a newly keyed member and
  /// should ring the key-sweep doorbell).
  Future<bool> _ensureChatKeyPublished(Server server) async {
    final seed = _vaultCubit.state.masterSeed;
    if (seed == null) return false;
    // The publish guard is per identity, not per app run: after a vault reset
    // + rejoin in the same run, the new user's key must still be published —
    // a stale guard here leaves the member unkeyed and unable to ever be
    // granted channel access (ISSUES.md #1).
    if (seed != _publishedChatKeySeed) {
      _publishedChatKey.clear();
      _setPublishedChatKeySeed(seed);
    }
    if (_publishedChatKey.contains(server.id)) return false;
    final identity = await _chatIdentity(server);
    if (identity == null) return false;
    final response = await _serverCubit.publishChatKey(
      identity.publicKeyBase64,
    );
    if (!response.success) return false;
    _publishedChatKey.add(server.id);
    final data = response.data as Map<String, dynamic>?;
    return data?['newly_published'] == true;
  }

  /// Fetch + unwrap the keyring for [channelId]; bootstrap v1 when the
  /// channel has no key yet; heal members missing current-version entries.
  Future<_KeyringResult> _loadOrBootstrapKeyring(String channelId) async {
    _keys.clear();
    _setCurrentKeyVersion(0);

    final server = _serverCubit.state.selectedServer;
    if (server == null) {
      return const _KeyringResult.failed(ChatFailure.noServer());
    }
    final identity = await _chatIdentity(server);
    if (identity == null) {
      return const _KeyringResult.failed(ChatFailure.vaultLocked());
    }

    // Bootstrap can race another member: retry once on conflict, using the
    // winner's keyring.
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _serverCubit.getChannelKey(channelId);
      if (!response.success) {
        return _KeyringResult.failed(ChatFailure.fromResponse(response));
      }

      final data = response.data as Map<String, dynamic>;
      final currentVersion = data['current_version'] as int;
      final myKeys = (data['my_keys'] as List).cast<Map<String, dynamic>>();
      final missing = (data['members_missing'] as List)
          .cast<Map<String, dynamic>>();

      if (currentVersion == 0) {
        // No key yet — we're the bootstrapper (or we lose the race and loop).
        final bootstrapped = await _bootstrapKeyring(
          channelId,
          identity,
          missing,
        );
        if (!bootstrapped.isWaiting) return bootstrapped;
        continue; // conflict — refetch the winner's keyring
      }

      // Unwrap every version sealed to us (full scrollback).
      for (final entry in myKeys) {
        try {
          final key = await _crypto.unwrapKey(
            wrapped: WrappedKey.fromJson(entry),
            myKeyPair: identity.keyPair,
          );
          _keys[entry['key_version'] as int] = key;
        } catch (e) {
          HelperMethods.printDebug('[Chat] unwrap failed: $e');
        }
      }
      _setCurrentKeyVersion(currentVersion);

      if (!_keys.containsKey(currentVersion)) {
        return const _KeyringResult.waiting();
      }

      // We hold the current key — heal anyone missing it (fire-and-forget).
      if (missing.isNotEmpty) {
        unawaited(_healMembers(channelId, currentVersion, missing));
      }
      return const _KeyringResult.ready();
    }
    // Both attempts hit the bootstrap race.
    return const _KeyringResult.failed(ChatFailure.keyringConflict());
  }

  /// Generate v1 and seal it to every keyed member (including ourselves).
  Future<_KeyringResult> _bootstrapKeyring(
    String channelId,
    ChatIdentity identity,
    List<Map<String, dynamic>> members,
  ) async {
    if (members.isEmpty) {
      return const _KeyringResult.failed(ChatFailure.noKeyedMembers());
    }

    final channelKey = _crypto.generateChannelKey();
    final entries = await _crypto.sealKeyringEntries(
      key: channelKey,
      members: members,
    );

    final response = await _serverCubit.postChannelKeys(
      channelId: channelId,
      keyVersion: 1,
      entries: entries,
    );

    if (response.success) {
      _keys[1] = channelKey;
      _setCurrentKeyVersion(1);
      return const _KeyringResult.ready();
    }
    if (response.errorCode == 'keyring_conflict') {
      // Not a failure: the caller refetches the winner's ring.
      return const _KeyringResult.waiting();
    }
    return _KeyringResult.failed(ChatFailure.fromResponse(response));
  }

  /// Seal the current channel key to members who lack an entry. Conflicts are
  /// fine — another client healed them first.
  Future<void> _healMembers(
    String channelId,
    int keyVersion,
    List<Map<String, dynamic>> members,
  ) async {
    final channelKey = _keys[keyVersion];
    if (channelKey == null) return;
    try {
      final entries = await _crypto.sealKeyringEntries(
        key: channelKey,
        members: members,
      );
      final response = await _serverCubit.postChannelKeys(
        channelId: channelId,
        keyVersion: keyVersion,
        entries: entries,
      );
      // Wake the healed members so their waiting screens refetch.
      if (response.success) _ringKeySweepDoorbell();
    } catch (e) {
      HelperMethods.printDebug('[Chat] heal failed: $e');
    }
  }
}
