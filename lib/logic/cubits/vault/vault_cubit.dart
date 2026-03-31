import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/encrypted_vault.dart';
import '../../../data/classes/vault.dart';
import '../../../data/enums/auth_status.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../../data/repositories/secure_storage_repository.dart';
import 'vault_state.dart';

/// Manages the user's encrypted vault lifecycle.
///
/// Responsibilities:
/// - Check whether a vault already exists on startup.
/// - Create a new vault (Phase 1 from auth.md).
/// - Unlock an existing vault with the master password (Phase 5).
class VaultCubit extends Cubit<VaultState> {
  final CryptoRepository _crypto;
  final SecureStorageRepository _storage;

  VaultCubit({
    CryptoRepository? crypto,
    SecureStorageRepository? storage,
  })  : _crypto = crypto ?? CryptoRepository(),
        _storage = storage ?? SecureStorageRepository(),
        super(const VaultState());

  // ──────────────────────────────────────────────────────────
  // Startup check
  // ──────────────────────────────────────────────────────────

  /// Call once at app startup to determine auth status.
  Future<void> checkVaultStatus() async {
    try {
      final masterSeed = await _storage.getMasterSeed();
      if (masterSeed != null) {
        // Vault exists and seed is available — user is "unlocked".
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

  /// Create a brand-new vault from a master password.
  ///
  /// 1. Generate 256-bit master seed.
  /// 2. Generate 256-bit global salt.
  /// 3. Derive vault key via Argon2id (runs in isolate).
  /// 4. Encrypt vault JSON with AES-GCM.
  /// 5. Store master seed + encrypted vault in secure storage.
  Future<void> createVault(String password) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      // 1. Generate master seed
      final masterSeed = _crypto.generateMasterSeed();
      final masterSeedB64 = CryptoRepository.toBase64(masterSeed);

      // 2. Generate global salt
      final globalSalt = _crypto.generateSalt();

      // 3. Derive vault key (heavy — runs in isolate)
      final vaultKey = await _crypto.deriveVaultKey(
        password: password,
        salt: globalSalt,
      );

      // 4. Build & encrypt the vault
      final vault = Vault(masterSeed: masterSeedB64);
      final encrypted = await _crypto.encrypt(
        plaintext: vault.toJsonString(),
        key: vaultKey,
      );

      // 5. Persist to secure storage
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
}

