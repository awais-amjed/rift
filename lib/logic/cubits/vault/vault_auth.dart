part of 'vault_cubit.dart';

mixin _VaultAuthMixin on Cubit<VaultState> {
  SecureStorageRepository get _storage;
  ServerRepository get _serverRepo;
  CryptoRepository get _crypto;
  Future<ServerIdentity> getIdentityForHost(String host, {String version = 'v1'});

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
  // Phase 3: Challenge-response login
  // ──────────────────────────────────────────────────────────

  /// Performs a challenge-response handshake and returns a session token.
  Future<({bool success, String? error, Map<String, dynamic>? data})>
      loginToServer({
    required String supabaseUrl,
    required String serverId,
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;

      // Resolve the current key version so logins work after key rotation.
      final joinedServers = await _storage.getJoinedServers();
      final serverEntry = joinedServers
          .cast<({String url, String version})?>()
          .firstWhere((s) => s?.url == host, orElse: () => null);
      final version = serverEntry?.version ?? 'v1';

      final identity = await getIdentityForHost(host, version: version);

      final challengeResponse = await _serverRepo.getChallenge(
        supabaseUrl,
        publicKey: identity.publicKeyBase64,
        serverId: serverId,
      );

      if (!challengeResponse.success) {
        return (success: false, error: challengeResponse.error, data: null);
      }

      final nonce = challengeResponse.data['nonce'] as String;

      final signature = await _crypto.signChallenge(
        keyPair: identity.keyPair,
        nonce: nonce,
        host: host,
      );

      final verifyResponse = await _serverRepo.verifyChallenge(
        supabaseUrl,
        publicKey: identity.publicKeyBase64,
        nonce: nonce,
        signature: CryptoRepository.toBase64(signature),
        host: host,
        serverId: serverId,
      );

      if (!verifyResponse.success) {
        return (success: false, error: verifyResponse.error, data: null);
      }

      return (
        success: true,
        error: null,
        data: verifyResponse.data as Map<String, dynamic>,
      );
    } catch (e) {
      HelperMethods.printDebug('[Vault] loginToServer error: $e');
      return (success: false, error: e.toString(), data: null);
    }
  }
}

