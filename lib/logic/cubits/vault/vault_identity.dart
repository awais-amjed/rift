part of 'vault_cubit.dart';

mixin _VaultIdentityMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  ServerRepository get _serverRepo;
  Map<String, ServerIdentity> get _identityCache;
  Map<String, ChatIdentity> get _chatIdentityCache;
  Future<void> _addServerToVault(String host, {String version = 'v1'});
  Future<({String? accessToken, String? error})> siwsLogin(String supabaseUrl);

  // ──────────────────────────────────────────────────────────
  // Phase 2: Joining a server
  // ──────────────────────────────────────────────────────────

  /// Derive or retrieve the cached identity for a given host.
  Future<ServerIdentity> getIdentityForHost(
    String host, {
    String version = 'v1',
  }) async {
    final cacheKey = '$host:$version';
    if (_identityCache.containsKey(cacheKey)) {
      return _identityCache[cacheKey]!;
    }

    final seed = CryptoRepository.fromBase64(state.masterSeed!);
    final identity = await _crypto.deriveServerIdentity(
      masterSeed: seed,
      host: host,
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

    final seed = CryptoRepository.fromBase64(state.masterSeed!);
    final identity = await _crypto.deriveChatIdentity(
      masterSeed: seed,
      host: host,
      version: version,
    );
    _chatIdentityCache[cacheKey] = identity;
    return identity;
  }

  /// Register on a server with an invite code.
  Future<({bool success, String? error, Map<String, dynamic>? data})>
      registerOnServer({
    required String supabaseUrl,
    required String inviteCode,
    required String username,
    required String displayName,
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;
      final identity = await getIdentityForHost(host);

      // 1. SIWS login first — creates the GoTrue identity (signup) and yields
      //    the JWT that register binds the profile to (users.id = auth.uid()).
      final login = await siwsLogin(supabaseUrl);
      if (login.accessToken == null) {
        return (success: false, error: login.error, data: null);
      }
      final token = login.accessToken!;

      // 2. Create the server profile row.
      final response = await _serverRepo.register(
        supabaseUrl,
        bearerToken: token,
        inviteCode: inviteCode,
        publicKey: identity.publicKeyBase64,
        stableId: identity.stableId,
        username: username,
        displayName: displayName,
      );

      if (!response.success) {
        return (success: false, error: response.error, data: null);
      }

      await _addServerToVault(host, version: 'v1');

      return (
        success: true,
        error: null,
        data: <String, dynamic>{
          'token': token,
          ...(response.data as Map<String, dynamic>),
        },
      );
    } catch (e) {
      HelperMethods.printDebug('[Vault] registerOnServer error: $e');
      return (success: false, error: e.toString(), data: null);
    }
  }
}



