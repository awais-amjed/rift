import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/backup_file.dart';
import '../../../data/classes/encrypted_seed.dart';
import '../../../data/classes/encrypted_vault.dart';
import '../../../data/enums/auth_status.dart';
import '../../../logic/helper_methods.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../../data/repositories/secure_storage_repository.dart';
import '../../../data/repositories/server_repository.dart';

part 'vault_state.dart';
part 'vault_creation.dart';
part 'vault_identity.dart';
part 'vault_auth.dart';
part 'vault_backup.dart';

/// Manages the user's encrypted vault: creation, server identity derivation,
/// SIWS login, and backup export/import.
class VaultCubit extends Cubit<VaultState>
    with
        _VaultCreationMixin,
        _VaultIdentityMixin,
        _VaultAuthMixin,
        _VaultBackupMixin {
  @override
  final CryptoRepository _crypto;
  @override
  final SecureStorageRepository _storage;
  @override
  final ServerRepository _serverRepo;

  /// In-memory cache of derived keypairs per host to avoid redundant derivation.
  @override
  final Map<String, ServerIdentity> _identityCache = {};

  /// In-memory cache of derived X25519 chat identities per host.
  @override
  final Map<String, ChatIdentity> _chatIdentityCache = {};

  /// Called after a successful [importBackup] to reconcile the server list.
  /// Receives the full server metadata maps from the backup.
  @override
  void Function(List<Map<String, dynamic>>)? _onServersImported;

  void setOnServersImported(
    void Function(List<Map<String, dynamic>>) callback,
  ) {
    _onServersImported = callback;
  }

  /// Called during [exportBackup] to capture the current server list.
  @override
  List<Map<String, dynamic>> Function()? _getServersForExport;

  void setGetServersForExport(List<Map<String, dynamic>> Function() callback) {
    _getServersForExport = callback;
  }

  /// Called after the vault blob is re-encrypted (server joined, key rotated).
  /// Wired to the cloud auto-backup in main.dart.
  void Function()? _onVaultChanged;

  void setOnVaultChanged(void Function() callback) {
    _onVaultChanged = callback;
  }

  VaultCubit({
    CryptoRepository? crypto,
    SecureStorageRepository? storage,
    ServerRepository? serverRepo,
  }) : _crypto = crypto ?? CryptoRepository(),
       _storage = storage ?? SecureStorageRepository(),
       _serverRepo = serverRepo ?? ServerRepository(),
       super(const VaultState());

  // ──────────────────────────────────────────────────────────
  // Vault persistence helpers
  // ──────────────────────────────────────────────────────────

  /// Adds a joined server entry and re-encrypts the vault blob.
  @override
  Future<void> _addServerToVault(String host, {String version = 'v1'}) async {
    await _storage.addJoinedServer(host, version);
    await _syncVaultBlob();
  }

  /// Re-encrypts the vault blob from the current joined_servers list.
  /// Uses HMAC(masterSeed, "vault:v1") — always available without a password.
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
    await _storage.saveEncryptedVault(
      EncryptedVault(
        ciphertext: CryptoRepository.toBase64(encrypted.ciphertext),
        iv: CryptoRepository.toBase64(encrypted.iv),
      ),
    );

    _onVaultChanged?.call();
  }

  Future<List<({String url, String version})>> getJoinedServers() =>
      _storage.getJoinedServers();

  /// Wipes all secure storage and resets to [AuthStatus.fresh], sending the
  /// user back to onboarding.
  ///
  /// Used by "sign out of this device" (safe — the cloud backup preserves the
  /// identity) and by the debug reset. For a privacy-mode vault with no backup
  /// this destroys the identity permanently, so callers must confirm first.
  Future<void> resetVault() async {
    HelperMethods.printDebug(
      '[VaultCubit] resetVault() — wiping secure storage',
    );
    await _storage.deleteAll();
    _identityCache.clear();
    _chatIdentityCache.clear();
    emit(const VaultState(status: AuthStatus.fresh));
  }
}
