part of 'channel_chat_cubit.dart';

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
  int get _currentKeyVersion;
  void _setCurrentKeyVersion(int version);
  void _ringKeySweepDoorbell();


  Future<ChatIdentity?> _chatIdentity(Server server) async {
    if (_vaultCubit.state.masterSeed == null) return null;
    final host = Uri.parse(server.supabaseUrl).host;
    return _vaultCubit.getChatIdentityForHost(
      host,
      version: CryptoRepository.chatIdentityVersion,
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

  /// Pick up key versions minted since this channel was opened.
  ///
  /// Before rotation existed, a channel's current version could not change
  /// while you sat in it, so a client that already held a key had no reason to
  /// look again. A rotation breaks that: another member mints the next version
  /// and, until this client notices, it keeps sealing messages with a key the
  /// rest of the channel has moved off and cannot read what they send back.
  ///
  /// Deliberately additive, unlike [_loadOrBootstrapKeyring], which clears the
  /// ring before refilling it. That is right when opening a channel and wrong
  /// here: this runs on a doorbell, against a client that is working, and a
  /// momentary network failure must not cost it the keys it already holds.
  Future<void> _absorbNewKeyVersions(String channelId) async {
    final server = _serverCubit.state.selectedServer;
    if (server == null) return;
    final identity = await _chatIdentity(server);
    if (identity == null) return;

    final response = await _serverCubit.getChannelKey(channelId);
    if (!response.success || isClosed) return;

    final data = response.data as Map<String, dynamic>;
    final currentVersion = data['current_version'] as int;
    if (currentVersion <= _currentKeyVersion) return;

    for (final entry
        in (data['my_keys'] as List).cast<Map<String, dynamic>>()) {
      final version = entry['key_version'] as int;
      if (_keys.containsKey(version)) continue;
      try {
        _keys[version] = await _crypto.unwrapKey(
          wrapped: WrappedKey.fromJson(entry),
          myKeyPair: identity.keyPair,
        );
      } catch (e) {
        HelperMethods.printDebug('[Chat] unwrap failed: $e');
      }
    }

    // Only move up once the new key is actually in hand. Announcing a version
    // we cannot seal with would break sending outright, where staying put
    // leaves the client working until the rotation reaches it.
    if (_keys.containsKey(currentVersion)) {
      _setCurrentKeyVersion(currentVersion);
    }
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
