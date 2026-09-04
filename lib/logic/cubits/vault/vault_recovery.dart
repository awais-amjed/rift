part of 'vault_cubit.dart';

/// The recovery key: issuing it, retiring it, and using it.
///
/// The password blob and the recovery blob wrap the same master seed under two
/// unrelated keys, so everything here is deliberately independent of the
/// password path. Changing the password does not touch the recovery blob and
/// does not need to — the plaintext underneath both is the seed, and the seed
/// never changes.
mixin _VaultRecoveryMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  SecureStorageRepository get _storage;

  /// Wrap [masterSeedB64] under a freshly generated recovery key.
  ///
  /// Returns the key in display form. It is stored as "pending" at the same
  /// time, which is what makes the acknowledgement screen survive being closed
  /// — see [SecureStorageRepository.savePendingRecoveryKey]. The caller shows
  /// it once; after [acknowledgeRecoveryKey] nothing on this device can
  /// produce it again.
  Future<String> _issueRecoveryKey(String masterSeedB64) async {
    final key = _crypto.generateRecoveryKey();
    final normalized = _crypto.normalizeRecoveryKey(key)!;

    final salt = _crypto.generateSalt();
    final recoveryKey = await _crypto.deriveVaultKey(
      password: normalized,
      salt: salt,
    );
    final wrapped = await _crypto.encrypt(
      plaintext: masterSeedB64,
      key: recoveryKey,
    );

    await _storage.saveRecoverySeed(
      EncryptedSeed(
        ciphertext: CryptoRepository.toBase64(wrapped.ciphertext),
        iv: CryptoRepository.toBase64(wrapped.iv),
        salt: CryptoRepository.toBase64(salt),
      ),
    );
    await _storage.savePendingRecoveryKey(key);
    return key;
  }

  /// Load any unacknowledged key so the router can insist on showing it.
  Future<String?> loadPendingRecoveryKey() => _storage.getPendingRecoveryKey();

  /// The person says they have written it down. Take our copy away.
  ///
  /// This is the point of no return by design: keeping it would turn a written
  /// key into decoration, since anyone with the device would have both halves.
  Future<void> acknowledgeRecoveryKey() async {
    await _storage.clearPendingRecoveryKey();
    emit(state.copyWith(clearPendingRecoveryKey: true));
  }

  /// Replace the recovery key, proving the password first.
  ///
  /// Requires the password for the same reason the change-password flow does:
  /// without it, anyone who found an unlocked device could mint themselves a
  /// permanent way back into the vault long after losing access to the device.
  /// The old key stops working the instant the new blob is written.
  Future<({bool success, String? error, String? key})> regenerateRecoveryKey({
    required String password,
  }) async {
    try {
      final seedBlob = await _storage.getEncryptedSeed();
      if (seedBlob == null) {
        return (success: false, error: 'Vault not initialised', key: null);
      }

      final key = await _crypto.deriveVaultKey(
        password: password,
        salt: CryptoRepository.fromBase64(seedBlob.salt),
      );
      final masterSeedB64 = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(seedBlob.ciphertext),
        key: key,
        iv: CryptoRepository.fromBase64(seedBlob.iv),
      );

      final fresh = await _issueRecoveryKey(masterSeedB64);
      emit(state.copyWith(pendingRecoveryKey: fresh));
      return (success: true, error: null, key: fresh);
    } on SecretBoxAuthenticationError {
      return (success: false, error: 'Wrong password', key: null);
    } catch (e) {
      HelperMethods.printDebug('[Vault] regenerateRecoveryKey error: $e');
      return (success: false, error: e.toString(), key: null);
    }
  }

  /// Turn a typed recovery key into the master seed it unwraps.
  ///
  /// [blob] is the recovery wrap — from local storage when the vault is on
  /// this device, or from a backup file when it is not. Rejects an
  /// ill-formed key before running Argon2id, so an obvious typo comes back
  /// immediately instead of after a second of CPU.
  Future<({String? masterSeedB64, String? error})> unwrapWithRecoveryKey({
    required EncryptedSeed blob,
    required String recoveryKey,
  }) async {
    final normalized = _crypto.normalizeRecoveryKey(recoveryKey);
    if (normalized == null) {
      return (
        masterSeedB64: null,
        error: 'That does not look like a recovery key',
      );
    }

    try {
      final key = await _crypto.deriveVaultKey(
        password: normalized,
        salt: CryptoRepository.fromBase64(blob.salt),
      );
      final masterSeedB64 = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(blob.ciphertext),
        key: key,
        iv: CryptoRepository.fromBase64(blob.iv),
      );
      return (masterSeedB64: masterSeedB64, error: null);
    } on SecretBoxAuthenticationError {
      return (masterSeedB64: null, error: 'That recovery key does not match');
    } catch (e) {
      HelperMethods.printDebug('[Vault] unwrapWithRecoveryKey error: $e');
      return (masterSeedB64: null, error: e.toString());
    }
  }
}
