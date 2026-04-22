part of 'vault_cubit.dart';

mixin _VaultKeyRotationMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  SecureStorageRepository get _storage;
  ServerRepository get _serverRepo;
  Map<String, ServerIdentity> get _identityCache;
  Future<ServerIdentity> getIdentityForHost(String host, {String version = 'v1'});
  Future<void> _syncVaultBlob();

  // ──────────────────────────────────────────────────────────
  // Phase 4: Key rotation
  // ──────────────────────────────────────────────────────────

  /// Rotate the Ed25519 keypair for a server.
  Future<({bool success, String? error, String? newVersion})> rotateKey({
    required String supabaseUrl,
    required String serverId,
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;

      final joinedServers = await _storage.getJoinedServers();
      final serverEntry = joinedServers
          .cast<({String url, String version})?>()
          .firstWhere((s) => s?.url == host, orElse: () => null);
      final currentVersion = serverEntry?.version ?? 'v1';
      final newVersion = _bumpVersion(currentVersion);

      final oldIdentity = await getIdentityForHost(host, version: currentVersion);
      final newIdentity = await getIdentityForHost(host, version: newVersion);

      // Obtain a server-issued challenge to prevent replay attacks.
      final challengeResponse = await _serverRepo.getChallenge(
        supabaseUrl,
        publicKey: oldIdentity.publicKeyBase64,
        serverId: serverId,
      );
      if (!challengeResponse.success) {
        return (success: false, error: challengeResponse.error, newVersion: null);
      }
      final nonce = challengeResponse.data['nonce'] as String;

      // Sign rotate:<newPubKey>@<nonce>@<host> with the old private key.
      final signature = await _crypto.signRotation(
        oldKeyPair: oldIdentity.keyPair,
        newPublicKeyBytes: newIdentity.publicKeyBytes,
        nonce: nonce,
        host: host,
      );

      final response = await _serverRepo.rotateKey(
        supabaseUrl,
        oldPublicKey: oldIdentity.publicKeyBase64,
        newPublicKey: newIdentity.publicKeyBase64,
        nonce: nonce,
        signature: CryptoRepository.toBase64(signature),
        host: host,
        serverId: serverId,
      );

      if (!response.success) {
        return (success: false, error: response.error, newVersion: null);
      }

      await _storage.updateServerVersion(host, newVersion);
      _identityCache.remove('$host:$currentVersion');

      // Keep the vault blob in sync so the next export reflects the rotation.
      await _syncVaultBlob();

      return (success: true, error: null, newVersion: newVersion);
    } catch (e) {
      HelperMethods.printDebug('[Vault] rotateKey error: $e');
      return (success: false, error: e.toString(), newVersion: null);
    }
  }

  static String _bumpVersion(String version) {
    final match = RegExp(r'v(\d+)').firstMatch(version);
    if (match == null) return 'v2';
    final num = int.parse(match.group(1)!);
    return 'v${num + 1}';
  }
}

