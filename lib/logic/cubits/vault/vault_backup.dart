part of 'vault_cubit.dart';

mixin _VaultBackupMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;

  /// Implemented by [_VaultRecoveryMixin].
  Future<({String? masterSeedB64, String? error})> unwrapWithRecoveryKey({
    required EncryptedSeed blob,
    required String recoveryKey,
  });

  SecureStorageRepository get _storage;
  Map<String, ServerIdentity> get _identityCache;
  void Function(List<Map<String, dynamic>>)? get _onServersImported;
  List<Map<String, dynamic>> Function()? get _getServersForExport;

  // ──────────────────────────────────────────────────────────
  // Phase 5: Backup export / import
  // ──────────────────────────────────────────────────────────

  /// Builds a [BackupFile] JSON string from the locally stored blobs.
  /// The servers list is encrypted with the vault key so the backup is fully
  /// opaque — no plaintext metadata is exposed to the storage provider.
  Future<({bool success, String? content, String? error})>
  exportBackup() async {
    try {
      final encryptedSeed = await _storage.getEncryptedSeed();
      final encryptedVault = await _storage.getEncryptedVault();

      if (encryptedSeed == null || encryptedVault == null) {
        return (success: false, content: null, error: 'Vault not initialised');
      }

      final masterSeedB64 = state.masterSeed;
      if (masterSeedB64 == null) {
        return (success: false, content: null, error: 'Vault is locked');
      }

      final servers = _getServersForExport?.call() ?? [];
      final serversJson = jsonEncode(servers);

      // Encrypt the servers list with the same vault key (HMAC(masterSeed,
      // "vault:v1")) but a fresh IV so the ciphertext is independent.
      final masterSeedBytes = CryptoRepository.fromBase64(masterSeedB64);
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeedBytes);
      final encryptedServers = await _crypto.encrypt(
        plaintext: serversJson,
        key: vaultKey,
      );

      final backup = BackupFile(
        version: BackupFile.currentVersion,
        seed: encryptedSeed,
        vault: encryptedVault,
        // Travels with the file, or the recovery key would only ever work on
        // the device that generated it — which is the one device you do not
        // need a recovery key for.
        recovery: await _storage.getRecoverySeed(),
        encryptedServers: EncryptedVault(
          ciphertext: CryptoRepository.toBase64(encryptedServers.ciphertext),
          iv: CryptoRepository.toBase64(encryptedServers.iv),
        ),
      );

      return (success: true, content: backup.toJsonString(), error: null);
    } catch (e) {
      HelperMethods.printDebug('[Vault] exportBackup error: $e');
      return (success: false, content: null, error: e.toString());
    }
  }

  /// Restores a vault from a [BackupFile] JSON string.
  ///
  /// Opened with [password], or with [recoveryKey] when the password is the
  /// thing that was lost. They are alternatives, not a fallback chain: the two
  /// blobs wrap the same seed under unrelated keys, so trying both would only
  /// mean reporting the wrong one as wrong.
  ///
  /// On success emits [AuthStatus.unlocked] and fully populates secure storage.
  Future<({bool success, String? error})> importBackup({
    required String jsonContent,
    String? password,
    String? recoveryKey,
  }) async {
    assert(
      (password == null) != (recoveryKey == null),
      'importBackup takes a password or a recovery key, not both and not neither',
    );
    emit(state.copyWith(isProcessing: true, clearError: true));

    try {
      final backup = BackupFile.fromJsonString(jsonContent);

      final String masterSeedB64;
      if (recoveryKey != null) {
        final blob = backup.recovery;
        if (blob == null) {
          const msg = 'This backup has no recovery key on it';
          emit(state.copyWith(isProcessing: false, error: msg));
          return (success: false, error: msg);
        }
        final unwrapped = await unwrapWithRecoveryKey(
          blob: blob,
          recoveryKey: recoveryKey,
        );
        if (unwrapped.masterSeedB64 == null) {
          emit(state.copyWith(isProcessing: false, error: unwrapped.error));
          return (success: false, error: unwrapped.error);
        }
        masterSeedB64 = unwrapped.masterSeedB64!;
      } else {
        final salt = CryptoRepository.fromBase64(backup.seed.salt);
        final seedKey = await _crypto.deriveVaultKey(
          password: password!,
          salt: salt,
        );
        masterSeedB64 = await _crypto.decrypt(
          ciphertext: CryptoRepository.fromBase64(backup.seed.ciphertext),
          key: seedKey,
          iv: CryptoRepository.fromBase64(backup.seed.iv),
        );
      }

      final masterSeedBytes = CryptoRepository.fromBase64(masterSeedB64);
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeedBytes);
      final vaultJson = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(backup.vault.ciphertext),
        key: vaultKey,
        iv: CryptoRepository.fromBase64(backup.vault.iv),
      );

      final vaultData = jsonDecode(vaultJson) as Map<String, dynamic>;
      final rawServers = vaultData['joined_servers'] as List<dynamic>;
      final joinedServers = rawServers.map((e) {
        final m = e as Map<String, dynamic>;
        return (url: m['url'] as String, version: m['version'] as String);
      }).toList();

      await _storage.saveMasterSeed(masterSeedB64);
      await _storage.setJoinedServers(joinedServers);
      await _storage.saveEncryptedSeed(backup.seed);
      await _storage.saveEncryptedVault(backup.vault);
      if (backup.recovery != null) {
        await _storage.saveRecoverySeed(backup.recovery!);
      }

      _identityCache.clear();

      emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeedB64));

      // Decrypt the servers list and pass full metadata to ServerCubit.
      List<Map<String, dynamic>> serverMaps = [];
      if (backup.encryptedServers != null) {
        final serversJson = await _crypto.decrypt(
          ciphertext: CryptoRepository.fromBase64(
            backup.encryptedServers!.ciphertext,
          ),
          key: vaultKey,
          iv: CryptoRepository.fromBase64(backup.encryptedServers!.iv),
        );
        serverMaps = (jsonDecode(serversJson) as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        // Legacy v1 backup — fall back to url/version stubs from vault blob.
        serverMaps = joinedServers
            .map(
              (s) => <String, dynamic>{
                'supabaseUrl': s.url,
                'keyVersion': s.version,
              },
            )
            .toList();
      }

      _onServersImported?.call(serverMaps);

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
