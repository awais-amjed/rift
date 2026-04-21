part of 'vault_cubit.dart';

mixin _VaultBackupMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;
  SecureStorageRepository get _storage;
  Map<String, ServerIdentity> get _identityCache;
  void Function(List<({String url, String version})>)? get _onServersImported;

  // ──────────────────────────────────────────────────────────
  // Phase 5: Backup export / import
  // ──────────────────────────────────────────────────────────

  /// Builds a [BackupFile] JSON string from the locally stored blobs.
  /// No cryptography runs here — both blobs are already encrypted.
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
      HelperMethods.printDebug('[Vault] exportBackup error: $e');
      return (success: false, content: null, error: e.toString());
    }
  }

  /// Restores a vault from a [BackupFile] JSON string and password.
  /// On success emits [AuthStatus.unlocked] and fully populates secure storage.
  Future<({bool success, String? error})> importBackup({
    required String jsonContent,
    required String password,
  }) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      final backup = BackupFile.fromJsonString(jsonContent);

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

      final masterSeedBytes = CryptoRepository.fromBase64(masterSeedB64);
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeedBytes);
      final vaultJson = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(backup.vault.ciphertext),
        key: vaultKey,
        iv: CryptoRepository.fromBase64(backup.vault.iv),
      );

      final vaultData = jsonDecode(vaultJson) as Map<String, dynamic>;
      final rawServers = vaultData['joined_servers'] as List<dynamic>;
      final servers = rawServers.map((e) {
        final m = e as Map<String, dynamic>;
        return (url: m['url'] as String, version: m['version'] as String);
      }).toList();

      await _storage.saveMasterSeed(masterSeedB64);
      await _storage.setJoinedServers(servers);
      await _storage.saveEncryptedSeed(backup.seed);
      await _storage.saveEncryptedVault(backup.vault);

      _identityCache.clear();

      emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeedB64));

      // Notify ServerCubit to reconcile its server list with the restored vault.
      _onServersImported?.call(servers);

      return (success: true, error: null);
    } on SecretBoxAuthenticationError {
      // AES-GCM MAC check failed — wrong password or corrupted backup.
      const msg = 'Wrong password or corrupted backup';
      HelperMethods.printDebug('[Vault] importBackup: $msg');
      emit(state.copyWith(isProcessing: false, error: msg));
      return (success: false, error: msg);
    } on Exception catch (e) {
      final msg = 'Failed to import backup: $e';
      HelperMethods.printDebug('[Vault] importBackup error: $e');
      emit(state.copyWith(isProcessing: false, error: msg));
      return (success: false, error: msg);
    }
  }
}



