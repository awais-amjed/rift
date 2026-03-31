import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/encrypted_vault.dart';
import '../../../data/classes/vault.dart';
import '../../../data/enums/auth_status.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../../data/repositories/secure_storage_repository.dart';
import '../../../data/repositories/server_repository.dart';
import 'vault_state.dart';

/// Manages the user's encrypted vault lifecycle.
///
/// Responsibilities:
/// - Check whether a vault already exists on startup.
/// - Create a new vault (Phase 1).
/// - Derive server identities and handle registration (Phase 2).
/// - Perform challenge-response login (Phase 3).
/// - Rotate Ed25519 keys for a server (Phase 4).
class VaultCubit extends Cubit<VaultState> {
  final CryptoRepository _crypto;
  final SecureStorageRepository _storage;
  final ServerRepository _serverRepo;

  /// In-memory cache of derived keypairs per host, so we don't re-derive
  /// on every API call within the same session.
  final Map<String, ServerIdentity> _identityCache = {};

  VaultCubit({
    CryptoRepository? crypto,
    SecureStorageRepository? storage,
    ServerRepository? serverRepo,
  })  : _crypto = crypto ?? CryptoRepository(),
        _storage = storage ?? SecureStorageRepository(),
        _serverRepo = serverRepo ?? ServerRepository(),
        super(const VaultState());

  // ──────────────────────────────────────────────────────────
  // Startup check
  // ──────────────────────────────────────────────────────────

  /// Call once at app startup to determine auth status.
  Future<void> checkVaultStatus() async {
    try {
      final masterSeed = await _storage.getMasterSeed();
      if (masterSeed != null) {
        emit(VaultState(
          status: AuthStatus.unlocked,
          masterSeed: masterSeed,
        ));
      } else {
        emit(const VaultState(status: AuthStatus.fresh));
      }
    } catch (e) {
      emit(VaultState(status: AuthStatus.fresh, error: e.toString()));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Phase 1: Account creation
  // ──────────────────────────────────────────────────────────

  /// Create a brand-new vault from a password.
  Future<void> createVault(String password) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      final masterSeed = _crypto.generateMasterSeed();
      final masterSeedB64 = CryptoRepository.toBase64(masterSeed);
      final globalSalt = _crypto.generateSalt();

      final vaultKey = await _crypto.deriveVaultKey(
        password: password,
        salt: globalSalt,
      );

      final vault = Vault(masterSeed: masterSeedB64);
      final encrypted = await _crypto.encrypt(
        plaintext: vault.toJsonString(),
        key: vaultKey,
      );

      await _storage.saveMasterSeed(masterSeedB64);
      await _storage.saveEncryptedVault(EncryptedVault(
        ciphertext: CryptoRepository.toBase64(encrypted.ciphertext),
        iv: CryptoRepository.toBase64(encrypted.iv),
        globalSalt: CryptoRepository.toBase64(globalSalt),
      ));

      emit(VaultState(
        status: AuthStatus.unlocked,
        masterSeed: masterSeedB64,
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessing: false,
        error: 'Failed to create vault: $e',
      ));
    }
  }

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

  /// Register on a server with an invite code.
  ///
  /// 1. Derive Ed25519 keypair + stable ID for this host.
  /// 2. Send public key, stable ID, invite code, username, display name.
  /// 3. On success, add the server to the vault and re-encrypt.
  /// 4. Returns the registration response data on success.
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

      final response = await _serverRepo.register(
        supabaseUrl,
        inviteCode: inviteCode,
        publicKey: identity.publicKeyBase64,
        stableId: identity.stableId,
        username: username,
        displayName: displayName,
      );

      if (!response.success) {
        return (success: false, error: response.error, data: null);
      }

      // Update vault with the new server
      await _addServerToVault(host);

      return (
        success: true,
        error: null,
        data: response.data as Map<String, dynamic>,
      );
    } catch (e) {
      return (success: false, error: e.toString(), data: null);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Phase 3: Challenge-response login
  // ──────────────────────────────────────────────────────────

  /// Perform a challenge-response handshake to get a session token.
  ///
  /// 1. Derive keypair for this host.
  /// 2. Request a nonce from /get_challenge.
  /// 3. Sign "nonce@host" with the private key.
  /// 4. Send signature to /verify_challenge.
  /// 5. Returns token + server details on success.
  Future<({bool success, String? error, Map<String, dynamic>? data})>
      loginToServer({
    required String supabaseUrl,
    String version = 'v1',
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;
      final identity = await getIdentityForHost(host, version: version);

      // Step 1: Get challenge
      final challengeResponse = await _serverRepo.getChallenge(
        supabaseUrl,
        publicKey: identity.publicKeyBase64,
      );

      if (!challengeResponse.success) {
        return (success: false, error: challengeResponse.error, data: null);
      }

      final nonce = challengeResponse.data['nonce'] as String;

      // Step 2: Sign the challenge
      final signature = await _crypto.signChallenge(
        keyPair: identity.keyPair,
        nonce: nonce,
        host: host,
      );

      // Step 3: Verify
      final verifyResponse = await _serverRepo.verifyChallenge(
        supabaseUrl,
        publicKey: identity.publicKeyBase64,
        nonce: nonce,
        signature: CryptoRepository.toBase64(signature),
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
      return (success: false, error: e.toString(), data: null);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Phase 4: Key rotation
  // ──────────────────────────────────────────────────────────

  /// Rotate the Ed25519 keypair for a server.
  ///
  /// 1. Derive OLD identity (current version).
  /// 2. Derive NEW identity (bumped version).
  /// 3. Sign the new public key with the old private key.
  /// 4. Send to /rotate_key edge function.
  /// 5. Update stored version on success.
  /// Returns the new version string on success.
  Future<({bool success, String? error, String? newVersion})> rotateKey({
    required String supabaseUrl,
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;

      // Look up current version from secure storage
      final joinedServers = await _storage.getJoinedServers();
      final serverEntry = joinedServers.cast<({String url, String version})?>().firstWhere(
        (s) => s?.url == host,
        orElse: () => null,
      );
      final currentVersion = serverEntry?.version ?? 'v1';
      final newVersion = _bumpVersion(currentVersion);

      // Derive old and new identities
      final oldIdentity = await getIdentityForHost(host, version: currentVersion);
      final newIdentity = await getIdentityForHost(host, version: newVersion);

      // Sign the rotation payload with the old key
      final signature = await _crypto.signRotation(
        oldKeyPair: oldIdentity.keyPair,
        newPublicKeyBytes: newIdentity.publicKeyBytes,
        host: host,
      );

      // Call the edge function
      final response = await _serverRepo.rotateKey(
        supabaseUrl,
        oldPublicKey: oldIdentity.publicKeyBase64,
        newPublicKey: newIdentity.publicKeyBase64,
        signature: CryptoRepository.toBase64(signature),
      );

      if (!response.success) {
        return (success: false, error: response.error, newVersion: null);
      }

      // Update the stored version
      await _storage.updateServerVersion(host, newVersion);

      // Invalidate the old identity cache entry
      _identityCache.remove('$host:$currentVersion');

      return (success: true, error: null, newVersion: newVersion);
    } catch (e) {
      return (success: false, error: e.toString(), newVersion: null);
    }
  }

  /// Increment a version string: 'v1' → 'v2', 'v2' → 'v3', etc.
  static String _bumpVersion(String version) {
    final match = RegExp(r'v(\d+)').firstMatch(version);
    if (match == null) return 'v2';
    final num = int.parse(match.group(1)!);
    return 'v${num + 1}';
  }

  // ──────────────────────────────────────────────────────────
  // Vault persistence helpers
  // ──────────────────────────────────────────────────────────

  /// Add a server to the vault's joined_servers list and re-encrypt.
  Future<void> _addServerToVault(String host, {String version = 'v1'}) async {
    final encryptedVault = await _storage.getEncryptedVault();
    if (encryptedVault == null) return;

    // We need the vault key to re-encrypt — but we don't keep it in memory.
    // Instead, we just update the master seed's associated vault record.
    // Since the unencrypted vault data is only needed for cloud sync,
    // and we have the master seed locally, we store the updated joined_servers
    // list alongside the encrypted vault for now.
    await _storage.addJoinedServer(host, version);
  }

  /// Get the list of joined server hosts from secure storage.
  Future<List<({String url, String version})>> getJoinedServers() async {
    return _storage.getJoinedServers();
  }
}
