part of 'vault_cubit.dart';

mixin _VaultIdentityMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  ServerRepository get _serverRepo;
  ServerPassRepository get _passRepo;
  Map<String, ServerIdentity> get _identityCache;
  Map<String, ChatIdentity> get _chatIdentityCache;
  Future<void> _addServerToVault(String host, {String version = 'v1'});
  Future<({String? accessToken, String? error})> siwsLogin(
    String supabaseUrl, {
    required String serverId,
  });

  /// Implemented by [_VaultAuthMixin].
  Future<VaultState> settled();

  /// The master seed, once the vault has been read.
  ///
  /// Throws rather than returning null: there is no identity to derive
  /// without one, and a caller has nothing sensible to do with a null.
  Future<Uint8List> _masterSeed() async {
    final seed = (await settled()).masterSeed;
    if (seed == null) throw StateError('The vault has no master seed');
    return CryptoRepository.fromBase64(seed);
  }

  // ── Joining a server ──────────────────────────────────────

  /// Derive or retrieve the cached auth identity for a host.
  ///
  /// [serverId] scopes the identity to a specific server so multiple servers on
  /// one Supabase host (project) get distinct SIWS identities. It is null only
  /// for the central host (see [central_dm]); self-hosted callers pass the
  /// server id.
  Future<ServerIdentity> getIdentityForHost(
    String host, {
    String? serverId,
    String version = 'v1',
  }) async {
    final cacheKey = '$host:${serverId ?? ''}:$version';
    if (_identityCache.containsKey(cacheKey)) {
      return _identityCache[cacheKey]!;
    }

    final seed = await _masterSeed();
    final identity = await _crypto.deriveServerIdentity(
      masterSeed: seed,
      host: host,
      serverId: serverId,
      version: version,
    );
    _identityCache[cacheKey] = identity;
    return identity;
  }

  /// Derive or retrieve the cached X25519 chat identity for a given host
  /// (E2E messaging — ARCHITECTURE.md §4). Same per-host/versioned scheme as
  /// the Ed25519 auth identity, domain-separated in the derivation context.
  Future<ChatIdentity> getChatIdentityForHost(
    String host, {
    String version = 'v1',
  }) async {
    final cacheKey = '$host:$version';
    if (_chatIdentityCache.containsKey(cacheKey)) {
      return _chatIdentityCache[cacheKey]!;
    }

    final seed = await _masterSeed();
    final identity = await _crypto.deriveChatIdentity(
      masterSeed: seed,
      host: host,
      version: version,
    );
    _chatIdentityCache[cacheKey] = identity;
    return identity;
  }

  /// Register on a server with an invite code.
  ///
  /// [serverUrl] in the answer is the address joined, for the server to be
  /// kept under: a link that needs a Rift account is joined at the server's
  /// own address, which may not be the link's (`joinAddress`).
  Future<
    ({
      bool success,
      String? error,
      Map<String, dynamic>? data,
      String? serverUrl,
    })
  >
  registerOnServer({
    required String supabaseUrl,
    required String inviteCode,
    required String username,
    required String displayName,
  }) async {
    ({
      bool success,
      String? error,
      Map<String, dynamic>? data,
      String? serverUrl,
    })
    failed(String? error) =>
        (success: false, error: error, data: null, serverUrl: null);

    try {
      // 1. Resolve the invite to its server id BEFORE deriving the identity:
      //    with multiple servers per Supabase project the identity is scoped to
      //    (host, serverId), so we must know the server first — ARCHITECTURE.md §1.
      var resolved = await _serverRepo.resolveInvite(supabaseUrl, inviteCode);
      if (!resolved.success || resolved.serverId == null) {
        return failed(resolved.error ?? 'Invalid invite');
      }

      // A pass goes only to the address it names, so a link that needs an
      // account and reached the server another way is joined, whole, at the
      // address the server gives as its own. That address must be the same
      // server knowing the same invite: a server naming another's gets no
      // pass for it.
      final joinUrl = resolved.joinUrl ?? supabaseUrl;
      if (joinUrl != supabaseUrl) {
        final ownHost = Uri.parse(joinUrl).host;
        final there = await _serverRepo.resolveInvite(joinUrl, inviteCode);
        if (!there.success) {
          return failed(
            "This server couldn't be reached at its own address, $ownHost, "
            'which a link that needs a Rift account joins through.',
          );
        }
        if (there.serverId != resolved.serverId) {
          return failed(
            'This link gives the address of a different server, $ownHost.',
          );
        }
        resolved = there;
      }
      final serverId = resolved.serverId!;
      final host = Uri.parse(joinUrl).host;

      final identity = await getIdentityForHost(host, serverId: serverId);

      // 2. SIWS login — creates the per-(host, serverId) GoTrue identity (signup)
      //    and yields the JWT that register binds the profile to
      //    (users.id = auth.uid()).
      final login = await siwsLogin(joinUrl, serverId: serverId);
      if (login.accessToken == null) return failed(login.error);
      final token = login.accessToken!;

      // Central vouches for the account to this server and this identity.
      // Asked last, just before register, since a pass lives five minutes.
      // Without an account nothing is asked: the server lets somebody who
      // is already a member back, and refuses anybody new in its own words.
      String? pass;
      if (resolved.needsAccount && _passRepo.hasAccount) {
        final vouched = await _passRepo.passFor(
          supabaseUrl: joinUrl,
          serverId: serverId,
          publicKey: identity.publicKeyBase64,
        );
        if (vouched.pass == null) return failed(vouched.error);
        pass = vouched.pass;
      }

      // 3. Create the server profile row — or, for somebody who left and is
      //    coming back, sign in to the one they already have (the response
      //    then carries `rejoined: true`; see `register` in API.md).
      final response = await _serverRepo.register(
        joinUrl,
        bearerToken: token,
        inviteCode: inviteCode,
        publicKey: identity.publicKeyBase64,
        stableId: identity.stableId,
        username: username,
        displayName: displayName,
        pass: pass,
      );

      if (!response.success) return failed(response.error);

      await _addServerToVault(host, version: 'v1');

      return (
        success: true,
        error: null,
        data: <String, dynamic>{
          'token': token,
          ...(response.data as Map<String, dynamic>),
        },
        serverUrl: joinUrl,
      );
    } catch (e) {
      HelperMethods.printDebug('[Vault] registerOnServer error: $e');
      return failed(e.toString());
    }
  }
}
