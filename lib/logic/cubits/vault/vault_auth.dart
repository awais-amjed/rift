part of 'vault_cubit.dart';

mixin _VaultAuthMixin on Cubit<VaultState> {
  SecureStorageRepository get _storage;
  ServerRepository get _serverRepo;
  CryptoRepository get _crypto;
  Future<ServerIdentity> getIdentityForHost(
    String host, {
    String? serverId,
    String version = 'v1',
  });

  // ──────────────────────────────────────────────────────────
  // Startup check
  // ──────────────────────────────────────────────────────────

  /// Checks for an existing vault in secure storage and sets initial auth status.
  Future<void> checkVaultStatus() async {
    try {
      final masterSeed = await _storage.getMasterSeed();
      if (masterSeed != null) {
        emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeed));
      } else {
        emit(const VaultState(status: AuthStatus.fresh));
      }
    } catch (e) {
      HelperMethods.printDebug('[Vault] checkVaultStatus error: $e');
      emit(VaultState(status: AuthStatus.fresh, error: e.toString()));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Sign-in-with-Web3 (SIWS) login
  // ──────────────────────────────────────────────────────────

  /// Sign a SIWS message with this server's Ed25519 key and exchange it for a
  /// GoTrue session via the `login` proxy. Returns the access token (JWT).
  /// Shared by both re-login and first-time registration. [serverId] scopes the
  /// identity so servers sharing a host (project) sign in as distinct users.
  Future<({String? accessToken, String? error})> siwsLogin(
    String supabaseUrl, {
    required String serverId,
  }) async {
    final host = Uri.parse(supabaseUrl).host;
    final identity = await getIdentityForHost(host, serverId: serverId);
    // The host picks the *key*; it is deliberately not written into the signed
    // message, which names a fixed domain so a server can live at any address —
    // a LAN IP, a plain-http hostname — that GoTrue would otherwise reject.
    final signed = await _crypto.signSiws(
      keyPair: identity.keyPair,
      publicKeyBytes: identity.publicKeyBytes,
    );
    final response = await _serverRepo.login(
      supabaseUrl,
      message: signed.message,
      signature: signed.signatureBase64,
    );
    if (!response.success) {
      return (accessToken: null, error: response.error);
    }
    final data = response.data as Map<String, dynamic>?;
    final accessToken = data?['access_token'] as String?;
    if (accessToken == null) {
      return (accessToken: null, error: 'Login returned no access token');
    }
    return (accessToken: accessToken, error: null);
  }

  /// Re-authenticate an existing server session: SIWS login for a fresh JWT,
  /// then refresh the server context. Returns `{token, ...context}`; callers
  /// (reAuthenticate) read `data['token']`.
  Future<({bool success, String? error, Map<String, dynamic>? data})>
  loginToServer({
    required String supabaseUrl,
    required String serverId,
    required String anonKey,
  }) async {
    try {
      final login = await siwsLogin(supabaseUrl, serverId: serverId);
      if (login.accessToken == null) {
        return (success: false, error: login.error, data: null);
      }
      final token = login.accessToken!;

      final data = <String, dynamic>{'token': token};
      final details = await _serverRepo.getServerDetails(
        supabaseUrl,
        anonKey: anonKey,
        bearerToken: token,
      );
      if (details.success && details.data is Map) {
        data.addAll(details.data as Map<String, dynamic>);
        data['token'] = token; // context no longer carries a token
      }
      return (success: true, error: null, data: data);
    } catch (e) {
      HelperMethods.printDebug('[Vault] loginToServer error: $e');
      return (success: false, error: e.toString(), data: null);
    }
  }
}
