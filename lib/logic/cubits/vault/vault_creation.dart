part of 'vault_cubit.dart';

mixin _VaultCreationMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  SecureStorageRepository get _storage;

  /// Implemented by [_VaultRecoveryMixin].
  Future<String> _issueRecoveryKey(String masterSeedB64);

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
      await _storage.saveEncryptedSeed(
        EncryptedSeed(
          ciphertext: CryptoRepository.toBase64(encSeed.ciphertext),
          iv: CryptoRepository.toBase64(encSeed.iv),
          salt: CryptoRepository.toBase64(salt),
        ),
      );
      await _storage.saveEncryptedVault(
        EncryptedVault(
          ciphertext: CryptoRepository.toBase64(encVault.ciphertext),
          iv: CryptoRepository.toBase64(encVault.iv),
        ),
      );

      // Issued here rather than offered later, because a recovery key is only
      // worth anything if it exists before the password is forgotten — and
      // nobody goes looking for one while they still remember it.
      final recoveryKey = await _issueRecoveryKey(masterSeedB64);

      emit(
        VaultState(
          status: AuthStatus.unlocked,
          masterSeed: masterSeedB64,
          pendingRecoveryKey: recoveryKey,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('[Vault] createVault error: $e');
      emit(
        state.copyWith(
          isProcessing: false,
          error: 'Failed to create vault: $e',
        ),
      );
    }
  }

  /// Whether [password] opens the current seed blob.
  ///
  /// Exists so a password can be checked *before* anything with a cost or a
  /// side effect happens — sending an email, starting a change that has to be
  /// unwound. Runs the same Argon2id as a real unlock, so it is a second of
  /// work, not a free comparison.
  Future<bool> verifyVaultPassword(String password) async {
    final seedBlob = await _storage.getEncryptedSeed();
    if (seedBlob == null) return false;
    try {
      final key = await _crypto.deriveVaultKey(
        password: password,
        salt: CryptoRepository.fromBase64(seedBlob.salt),
      );
      await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(seedBlob.ciphertext),
        key: key,
        iv: CryptoRepository.fromBase64(seedBlob.iv),
      );
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    } catch (e) {
      HelperMethods.printDebug('[Vault] verifyVaultPassword error: $e');
      return false;
    }
  }

  /// Re-encrypts the master seed under a new password.
  ///
  /// The master seed (and therefore every derived identity) is unchanged —
  /// only the [EncryptedSeed] blob is rewritten with a fresh salt. Fails
  /// without side effects if [oldPassword] doesn't decrypt the current blob.
  Future<({bool success, String? error})> changeVaultPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final currentSeed = await _storage.getEncryptedSeed();
      if (currentSeed == null) {
        return (success: false, error: 'Vault not initialized');
      }

      final oldKey = await _crypto.deriveVaultKey(
        password: oldPassword,
        salt: CryptoRepository.fromBase64(currentSeed.salt),
      );
      final masterSeedB64 = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(currentSeed.ciphertext),
        key: oldKey,
        iv: CryptoRepository.fromBase64(currentSeed.iv),
      );

      final newSalt = _crypto.generateSalt();
      final newKey = await _crypto.deriveVaultKey(
        password: newPassword,
        salt: newSalt,
      );
      final encSeed = await _crypto.encrypt(
        plaintext: masterSeedB64,
        key: newKey,
      );

      await _storage.saveEncryptedSeed(
        EncryptedSeed(
          ciphertext: CryptoRepository.toBase64(encSeed.ciphertext),
          iv: CryptoRepository.toBase64(encSeed.iv),
          salt: CryptoRepository.toBase64(newSalt),
        ),
      );

      return (success: true, error: null);
    } on SecretBoxAuthenticationError {
      return (success: false, error: 'Wrong password');
    } catch (e) {
      HelperMethods.printDebug('[Vault] changeVaultPassword error: $e');
      return (success: false, error: e.toString());
    }
  }
}
