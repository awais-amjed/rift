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

  Future<void> _touchWraps({String? seedWrapEmail, bool keepEmail});

  /// Wrap [masterSeedB64] under a freshly generated recovery key, writing
  /// nothing. Returns the key in display form and the wrap.
  Future<({String key, EncryptedSeed blob})> _wrapUnderNewRecoveryKey(
    String masterSeedB64,
  ) async {
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
    return (
      key: key,
      blob: EncryptedSeed(
        ciphertext: CryptoRepository.toBase64(wrapped.ciphertext),
        iv: CryptoRepository.toBase64(wrapped.iv),
        salt: CryptoRepository.toBase64(salt),
      ),
    );
  }

  /// Wrap [masterSeedB64] under a freshly generated recovery key and store it.
  ///
  /// Returns the key in display form. It is stored as "pending" at the same
  /// time, which is what makes the acknowledgement screen survive being closed
  /// — see [SecureStorageRepository.savePendingRecoveryKey]. The caller shows
  /// it once; after [acknowledgeRecoveryKey] nothing on this device can
  /// produce it again.
  Future<String> _issueRecoveryKey(String masterSeedB64) async {
    final fresh = await _wrapUnderNewRecoveryKey(masterSeedB64);
    // The key before the wrap: a kill between the two leaves a key to show
    // and the old wrap, which [settlePendingRecoveryKey] mends on the next
    // start. The other way round it left a wrap no key anyone saw opens.
    await _storage.savePendingRecoveryKey(fresh.key);
    await _storage.saveRecoverySeed(fresh.blob);
    await _touchWraps(keepEmail: true);
    return fresh.key;
  }

  /// Load any unacknowledged key so the router can insist on showing it.
  Future<String?> loadPendingRecoveryKey() => _storage.getPendingRecoveryKey();

  /// Makes the stored recovery wrap the one [pending] opens, when a kill came
  /// between saving the key and saving its wrap. Runs at start only while a
  /// key waits to be acknowledged, so its second of Argon2id is rare.
  Future<void> settlePendingRecoveryKey({
    required String masterSeedB64,
    required String pending,
  }) async {
    final blob = await _storage.getRecoverySeed();
    if (blob != null) {
      final opened = await unwrapWithRecoveryKey(
        blob: blob,
        recoveryKey: pending,
      );
      if (opened.masterSeedB64 == masterSeedB64) return;
    }
    final normalized = _crypto.normalizeRecoveryKey(pending);
    if (normalized == null) return;
    final salt = _crypto.generateSalt();
    final key = await _crypto.deriveVaultKey(password: normalized, salt: salt);
    final wrapped = await _crypto.encrypt(plaintext: masterSeedB64, key: key);
    await _storage.saveRecoverySeed(
      EncryptedSeed(
        ciphertext: CryptoRepository.toBase64(wrapped.ciphertext),
        iv: CryptoRepository.toBase64(wrapped.iv),
        salt: CryptoRepository.toBase64(salt),
      ),
    );
    await _touchWraps(keepEmail: true);
  }

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
        return (success: false, error: 'Vault not initialized', key: null);
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

  /// Replace the recovery key from the seed in memory, proving nothing.
  ///
  /// For a password reset on a signed-in device only, called once the account
  /// has accepted the emailed code. That code is the proof [regenerateRecoveryKey]
  /// asks the password for: an unlocked device alone does not mint a key.
  Future<({bool success, String? error})> reissueRecoveryKey() async {
    final masterSeedB64 = state.masterSeed;
    if (masterSeedB64 == null) {
      return (success: false, error: 'Vault is locked');
    }
    try {
      final fresh = await _issueRecoveryKey(masterSeedB64);
      emit(state.copyWith(pendingRecoveryKey: fresh));
      return (success: true, error: null);
    } catch (e) {
      HelperMethods.printDebug('[Vault] reissueRecoveryKey error: $e');
      return (success: false, error: e.toString());
    }
  }

  /// The password wrap as stored, with the account it is for, for putting
  /// back with [restoreSeedWrap] when a change has to be undone.
  Future<({EncryptedSeed? blob, String? email})> storedSeedWrap() async => (
    blob: await _storage.getEncryptedSeed(),
    email: await _storage.getSeedWrapEmail(),
  );

  Future<void> restoreSeedWrap(
    ({EncryptedSeed? blob, String? email}) wrap,
  ) async {
    final blob = wrap.blob;
    if (blob == null) return;
    await _storage.saveEncryptedSeed(blob);
    await _touchWraps(seedWrapEmail: wrap.email);
  }

  /// Re-wrap the in-memory master seed under [newPassword].
  ///
  /// Unlike [changeVaultPassword] this proves nothing first, because in the
  /// one flow that needs it there is nothing left to prove: the seed is
  /// already in hand, having just been unwrapped with a recovery key. The
  /// vault must be unlocked, which is the actual precondition. [wrapEmail] is
  /// the account [newPassword] is derived for, null for a typed one.
  Future<({bool success, String? error})> rewrapSeed({
    required String newPassword,
    required String? wrapEmail,
  }) async {
    final masterSeedB64 = state.masterSeed;
    if (masterSeedB64 == null) {
      return (success: false, error: 'Vault is locked');
    }

    try {
      final salt = _crypto.generateSalt();
      final key = await _crypto.deriveVaultKey(
        password: newPassword,
        salt: salt,
      );
      final wrapped = await _crypto.encrypt(plaintext: masterSeedB64, key: key);

      await _storage.saveEncryptedSeed(
        EncryptedSeed(
          ciphertext: CryptoRepository.toBase64(wrapped.ciphertext),
          iv: CryptoRepository.toBase64(wrapped.iv),
          salt: CryptoRepository.toBase64(salt),
        ),
      );
      await _touchWraps(seedWrapEmail: wrapEmail);
      return (success: true, error: null);
    } catch (e) {
      HelperMethods.printDebug('[Vault] rewrapSeed error: $e');
      return (success: false, error: e.toString());
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
