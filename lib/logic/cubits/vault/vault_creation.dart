part of 'vault_cubit.dart';

mixin _VaultCreationMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  SecureStorageRepository get _storage;

  // ──────────────────────────────────────────────────────────
  // Phase 1: Account creation
  // ──────────────────────────────────────────────────────────

  /// Creates a new vault from a password.
  /// Stores an [EncryptedSeed] (Argon2id-protected master seed) and an
  /// [EncryptedVault] (HMAC-protected server list) in secure storage.
  Future<void> createVault(String password) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      final masterSeed = _crypto.generateMasterSeed();
      final masterSeedB64 = CryptoRepository.toBase64(masterSeed);
      final salt = _crypto.generateSalt();

      final seedKey = await _crypto.deriveVaultKey(
        password: password,
        salt: salt,
      );

      final encSeed = await _crypto.encrypt(
        plaintext: masterSeedB64,
        key: seedKey,
      );

      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeed);

      final encVault = await _crypto.encrypt(
        plaintext: jsonEncode({'joined_servers': []}),
        key: vaultKey,
      );

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
      HelperMethods.printDebug('[Vault] createVault error: $e');
      emit(state.copyWith(
        isProcessing: false,
        error: 'Failed to create vault: $e',
      ));
    }
  }
}

