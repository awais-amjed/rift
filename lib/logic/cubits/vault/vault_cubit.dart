import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/backup_file.dart';
import '../../../data/classes/encrypted_seed.dart';
import '../../../data/classes/encrypted_vault.dart';
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
/// - Export / import a portable backup file (Phase 5).
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
        emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeed));
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
  ///
  /// Two blobs are produced and stored locally:
  ///   • EncryptedSeed  — Argon2id(password, salt) protects the master seed.
  ///                      Argon2id runs exactly once here; subsequent exports
  ///                      just read this pre-computed blob.
  ///   • EncryptedVault — HMAC(masterSeed, "vault:v1") protects joined_servers.
  ///                      Re-encrypted silently on every state change.
  Future<void> createVault(String password) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      // 1. Generate master seed and Argon2id salt
      final masterSeed = _crypto.generateMasterSeed();
      final masterSeedB64 = CryptoRepository.toBase64(masterSeed);
      final salt = _crypto.generateSalt();

      // 2. Derive seed encryption key (slow — runs in Isolate inside deriveVaultKey)
      final seedKey = await _crypto.deriveVaultKey(
        password: password,
        salt: salt,
      );

      // 3. Encrypt the master seed → EncryptedSeed
      final encSeed = await _crypto.encrypt(
        plaintext: masterSeedB64,
        key: seedKey,
      );

      // 4. Derive local vault key (fast — HMAC, no Isolate needed)
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeed);

      // 5. Encrypt empty joined_servers → EncryptedVault
      final encVault = await _crypto.encrypt(
        plaintext: jsonEncode({'joined_servers': []}),
        key: vaultKey,
      );

      // 6. Persist everything
      await _storage.saveMasterSeed(masterSeedB64);
      await _storage.saveEncryptedSeed(EncryptedSeed(
        ciphertext: CryptoRepository.toBase64(encSeed.ciphertext),
        iv: CryptoRepository.toBase64(encSeed.iv),
        salt: CryptoRepository.toBase64(salt),
      ));
      await _storage.saveEncryptedVault(EncryptedVault(
        ciphertext: CryptoRepository.toBase64(encVault.ciphertext),
        iv: CryptoRepository.toBase64(encVault.iv),
      ));

      emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeedB64));
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
  Future<({bool success, String? error, Map<String, dynamic>? data})>
      loginToServer({
    required String supabaseUrl,
  }) async {
    try {
      final host = Uri.parse(supabaseUrl).host;

      // Auto-resolve the current key version so logins work after key rotation.
      final joinedServers = await _storage.getJoinedServers();
      final serverEntry = joinedServers
          .cast<({String url, String version})?>()
          .firstWhere((s) => s?.url == host, orElse: () => null);
      final version = serverEntry?.version ?? 'v1';

      final identity = await getIdentityForHost(host, version: version);

      final challengeResponse = await _serverRepo.getChallenge(
        supabaseUrl,
        publicKey: identity.publicKeyBase64,
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
  Future<({bool success, String? error, String? newVersion})> rotateKey({
    required String supabaseUrl,
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

      final signature = await _crypto.signRotation(
        oldKeyPair: oldIdentity.keyPair,
        newPublicKeyBytes: newIdentity.publicKeyBytes,
        host: host,
      );

      final response = await _serverRepo.rotateKey(
        supabaseUrl,
        oldPublicKey: oldIdentity.publicKeyBase64,
        newPublicKey: newIdentity.publicKeyBase64,
        signature: CryptoRepository.toBase64(signature),
      );

      if (!response.success) {
        return (success: false, error: response.error, newVersion: null);
      }

      await _storage.updateServerVersion(host, newVersion);
      _identityCache.remove('$host:$currentVersion');

      // Keep the vault blob in sync so the next export is up to date.
      await _syncVaultBlob();

      return (success: true, error: null, newVersion: newVersion);
    } catch (e) {
      return (success: false, error: e.toString(), newVersion: null);
    }
  }

  static String _bumpVersion(String version) {
    final match = RegExp(r'v(\d+)').firstMatch(version);
    if (match == null) return 'v2';
    final num = int.parse(match.group(1)!);
    return 'v${num + 1}';
  }

  // ──────────────────────────────────────────────────────────
  // Phase 5: Backup export / import
  // ──────────────────────────────────────────────────────────

  /// Build a [BackupFile] JSON string ready to be written to disk.
  ///
  /// No cryptography runs here — both blobs are already stored locally and
  /// just get combined. Fast and password-free.
  Future<({bool success, String? content, String? error})>
      exportBackup() async {
    try {
      final encryptedSeed = await _storage.getEncryptedSeed();
      final encryptedVault = await _storage.getEncryptedVault();

      if (encryptedSeed == null || encryptedVault == null) {
        return (success: false, content: null, error: 'Vault not initialised');
      }

      final backup = BackupFile(
        version: BackupFile.currentVersion,
        seed: encryptedSeed,
        vault: encryptedVault,
      );

      return (success: true, content: backup.toJsonString(), error: null);
    } catch (e) {
      return (success: false, content: null, error: e.toString());
    }
  }

  /// Restore a vault from a [BackupFile] JSON string and password.
  ///
  /// On success, emits [AuthStatus.unlocked] and the local secure storage is
  /// fully populated — identical to a fresh vault creation.
  Future<({bool success, String? error})> importBackup({
    required String jsonContent,
    required String password,
  }) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      final backup = BackupFile.fromJsonString(jsonContent);

      // 1. Decrypt the master seed using Argon2id(password, salt)
      final salt = CryptoRepository.fromBase64(backup.seed.salt);
      final seedKey = await _crypto.deriveVaultKey(
        password: password,
        salt: salt,
      );
      final masterSeedB64 = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(backup.seed.ciphertext),
        key: seedKey,
        iv: CryptoRepository.fromBase64(backup.seed.iv),
      );

      // 2. Decrypt the joined_servers using HMAC(masterSeed, "vault:v1")
      final masterSeedBytes = CryptoRepository.fromBase64(masterSeedB64);
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeedBytes);
      final vaultJson = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(backup.vault.ciphertext),
        key: vaultKey,
        iv: CryptoRepository.fromBase64(backup.vault.iv),
      );

      // 3. Parse joined_servers
      final vaultData = jsonDecode(vaultJson) as Map<String, dynamic>;
      final rawServers = vaultData['joined_servers'] as List<dynamic>;
      final servers = rawServers.map((e) {
        final m = e as Map<String, dynamic>;
        return (url: m['url'] as String, version: m['version'] as String);
      }).toList();

      // 4. Persist everything
      await _storage.saveMasterSeed(masterSeedB64);
      await _storage.setJoinedServers(servers);
      await _storage.saveEncryptedSeed(backup.seed);
      await _storage.saveEncryptedVault(backup.vault);

      _identityCache.clear();

      emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeedB64));
      return (success: true, error: null);
    } on Exception catch (e) {
      // A decryption failure (wrong password) surfaces as a generic exception.
      final msg = e.toString().contains('mac')
          ? 'Wrong password or corrupted backup'
          : 'Failed to import backup: $e';
      emit(state.copyWith(isProcessing: false, error: msg));
      return (success: false, error: msg);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Vault persistence helpers
  // ──────────────────────────────────────────────────────────

  /// Track a newly joined server and silently re-encrypt the vault blob.
  Future<void> _addServerToVault(String host, {String version = 'v1'}) async {
    await _storage.addJoinedServer(host, version);
    await _syncVaultBlob();
  }

  /// Re-encrypt the vault blob from the current joined_servers list.
  ///
  /// Uses HMAC(masterSeed, "vault:v1") — always available without a password.
  /// Called after every state change (server join, key rotation) so the local
  /// blob is always ready for export.
  Future<void> _syncVaultBlob() async {
    if (state.masterSeed == null) return;

    final masterSeed = CryptoRepository.fromBase64(state.masterSeed!);
    final vaultKey = await _crypto.deriveLocalVaultKey(masterSeed);

    final servers = await _storage.getJoinedServers();
    final payload = jsonEncode({
      'joined_servers': servers
          .map((s) => {'url': s.url, 'version': s.version})
          .toList(),
    });

    final encrypted = await _crypto.encrypt(plaintext: payload, key: vaultKey);
    await _storage.saveEncryptedVault(EncryptedVault(
      ciphertext: CryptoRepository.toBase64(encrypted.ciphertext),
      iv: CryptoRepository.toBase64(encrypted.iv),
    ));
  }

  /// Get the list of joined server hosts from secure storage.
  Future<List<({String url, String version})>> getJoinedServers() =>
      _storage.getJoinedServers();
}
