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
part 'vault_key_rotation.dart';
part 'vault_backup.dart';

/// Manages the user's encrypted vault: creation, server identity derivation,
/// challenge-response login, key rotation, and backup export/import.
class VaultCubit extends Cubit<VaultState>
    with
        _VaultCreationMixin,
        _VaultIdentityMixin,
        _VaultAuthMixin,
        _VaultKeyRotationMixin,
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

  /// Called after a successful [importBackup] to reconcile the server list.
  @override
  void Function(List<({String url, String version})>)? _onServersImported;

  void setOnServersImported(
    void Function(List<({String url, String version})>) callback,
  ) {
    _onServersImported = callback;
  }

  VaultCubit({
    CryptoRepository? crypto,
    SecureStorageRepository? storage,
    ServerRepository? serverRepo,
  })  : _crypto = crypto ?? CryptoRepository(),
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
  @override
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

  Future<List<({String url, String version})>> getJoinedServers() =>
      _storage.getJoinedServers();

  // ──────────────────────────────────────────────────────────
  // Dev helpers
  // ──────────────────────────────────────────────────────────

  /// Wipes all secure storage and resets to [AuthStatus.fresh]. Dev/test only.
  /// Calling this in production destroys the user's identity permanently.
  Future<void> resetVault() async {
    assert(
      () {
        HelperMethods.printDebug('[VaultCubit] resetVault() called — dev/test only');
        return true;
      }(),
      'resetVault() must not be called in production builds.',
    );
    await _storage.deleteAll();
    _identityCache.clear();
    emit(const VaultState(status: AuthStatus.fresh));
  }
}
