part of 'vault_cubit.dart';

/// What [VaultCubit.syncWraps] found comparing a backup's wraps with this
/// device's.
enum WrapsSync {
  /// The backup's were newer and are this device's now.
  adopted,

  /// The same age: nothing to do either way.
  same,

  /// This device's are newer: the backup should be replaced.
  localNewer,
}

/// Over the cubit-part budget and one job: the vault's backup file, written
/// out and read back in.
///
/// Exporting a backup, importing one, and the two questions asked of a file
/// before that: which servers it holds, and whether it is this vault's.
mixin _VaultBackupMixin on Cubit<VaultState> {
  CryptoRepository get _crypto;

  /// Implemented by [_VaultRecoveryMixin].
  Future<({String? masterSeedB64, String? error})> unwrapWithRecoveryKey({
    required EncryptedSeed blob,
    required String recoveryKey,
  });

  SecureStorageRepository get _storage;
  Map<String, ServerIdentity> get _identityCache;
  Map<String, ChatIdentity> get _chatIdentityCache;
  void Function(ServerManifest)? get _onServersImported;
  ServerManifest Function()? get _getServersForExport;

  /// Implemented by [VaultCubit].
  Future<void> _forgetIdentity();

  /// Builds a [BackupFile] JSON string from the locally stored blobs.
  /// The servers list is encrypted with the vault key so the backup is fully
  /// opaque — no plaintext metadata is exposed to the storage provider.
  Future<({bool success, String? content, String? error})>
  exportBackup() async {
    try {
      final encryptedSeed = await _storage.getEncryptedSeed();
      final encryptedVault = await _storage.getEncryptedVault();

      if (encryptedSeed == null || encryptedVault == null) {
        return (success: false, content: null, error: 'Vault not initialized');
      }

      final masterSeedB64 = state.masterSeed;
      if (masterSeedB64 == null) {
        return (success: false, content: null, error: 'Vault is locked');
      }

      final manifest = _getServersForExport?.call() ?? ServerManifest.empty;
      // An object rather than the bare array v1 wrote, because the order the
      // array is in now has to travel with a clock saying how recent it is.
      final serversJson = jsonEncode(manifest.encode());

      // Encrypt the servers list with the same vault key (HMAC(masterSeed,
      // "vault:v1")) but a fresh IV so the ciphertext is independent.
      final masterSeedBytes = CryptoRepository.fromBase64(masterSeedB64);
      final vaultKey = await _crypto.deriveLocalVaultKey(masterSeedBytes);
      final encryptedServers = await _crypto.encrypt(
        plaintext: serversJson,
        key: vaultKey,
      );

      // Travels with the file, or the recovery key would only ever work on
      // the device that generated it — which is the one device you do not
      // need a recovery key for.
      final recovery = await _storage.getRecoverySeed();
      final wrapEmail = await _storage.getSeedWrapEmail();
      final wraps = await _crypto.encrypt(
        plaintext: jsonEncode({
          'at': await _storage.getWrapsAt(),
          'seed': encryptedSeed.toJson(),
          'recovery': ?recovery?.toJson(),
          'seed_email': ?wrapEmail,
        }),
        key: vaultKey,
      );

      final backup = BackupFile(
        version: BackupFile.currentVersion,
        seed: encryptedSeed,
        vault: encryptedVault,
        recovery: recovery,
        encryptedServers: EncryptedVault(
          ciphertext: CryptoRepository.toBase64(encryptedServers.ciphertext),
          iv: CryptoRepository.toBase64(encryptedServers.iv),
        ),
        wraps: EncryptedVault(
          ciphertext: CryptoRepository.toBase64(wraps.ciphertext),
          iv: CryptoRepository.toBase64(wraps.iv),
        ),
      );

      return (success: true, content: backup.toJsonString(), error: null);
    } catch (e) {
      HelperMethods.printDebug('[Vault] exportBackup error: $e');
      return (success: false, content: null, error: e.toString());
    }
  }

  /// Reads the server list out of a backup **without** restoring anything.
  ///
  /// Used before an upload, to combine what is already in the cloud with
  /// what this device holds rather than overwriting it. Safe to call on a
  /// backup another device wrote: the vault key is derived from the master
  /// seed, which both devices share, so the blob opens here — and if it does
  /// not open, the honest answer is null and the caller uploads its own copy
  /// rather than guessing at the contents.
  Future<ServerManifest?> readServerManifest(String backupJson) async {
    final masterSeedB64 = state.masterSeed;
    if (masterSeedB64 == null) return null;
    try {
      final backup = BackupFile.fromJsonString(backupJson);
      final blob = backup.encryptedServers;
      if (blob == null) return ServerManifest.empty;

      final vaultKey = await _crypto.deriveLocalVaultKey(
        CryptoRepository.fromBase64(masterSeedB64),
      );
      final json = await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(blob.ciphertext),
        key: vaultKey,
        iv: CryptoRepository.fromBase64(blob.iv),
      );
      return ServerManifest.decode(jsonDecode(json));
    } catch (e) {
      HelperMethods.printDebug('[Vault] readServerManifest failed: $e');
      return null;
    }
  }

  /// Whether [backupJson] is a backup of this vault — the same master seed,
  /// whoever uploaded it — rather than of another identity.
  ///
  /// Decided by opening its vault blob with the key this device derives from
  /// its own seed. AES-GCM opens only under the key that sealed it, so this is
  /// a proof, and it needs no password: the vault key is the seed's, not the
  /// password's. Anything that does not open, or does not parse, is "another".
  Future<bool> isBackupOfThisVault(String backupJson) async {
    final masterSeedB64 = state.masterSeed;
    if (masterSeedB64 == null) return false;
    try {
      final backup = BackupFile.fromJsonString(backupJson);
      final vaultKey = await _crypto.deriveLocalVaultKey(
        CryptoRepository.fromBase64(masterSeedB64),
      );
      await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(backup.vault.ciphertext),
        key: vaultKey,
        iv: CryptoRepository.fromBase64(backup.vault.iv),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The wraps sealed in [backup], when there are any this seed opens.
  Future<
    ({int at, EncryptedSeed seed, EncryptedSeed? recovery, String? email})?
  >
  _openWraps(BackupFile backup, Uint8List vaultKey) async {
    final sealed = backup.wraps;
    if (sealed == null) return null;
    try {
      final json =
          jsonDecode(
                await _crypto.decrypt(
                  ciphertext: CryptoRepository.fromBase64(sealed.ciphertext),
                  key: vaultKey,
                  iv: CryptoRepository.fromBase64(sealed.iv),
                ),
              )
              as Map<String, dynamic>;
      return (
        at: (json['at'] as num).toInt(),
        seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
        recovery: json['recovery'] == null
            ? null
            : EncryptedSeed.fromJson(json['recovery'] as Map<String, dynamic>),
        email: json['seed_email'] as String?,
      );
    } catch (e) {
      HelperMethods.printDebug('[Vault] backup wraps unreadable: $e');
      return null;
    }
  }

  /// Brings this device's seed and recovery wraps level with [backupJson]'s,
  /// which must be a backup of this vault.
  ///
  /// Each device uploads the wraps it holds. Before this a phone that had
  /// never heard of a recovery key replaced on the desktop uploaded the old
  /// one with its next backup: the new key stopped opening the cloud copy and
  /// the retired one worked again. Now the newer pair wins wherever it is
  /// met: adopted here when the backup's is newer, and reported when this
  /// device's is, so the caller uploads. Only wraps sealed under this seed's
  /// vault key count, so central cannot hand a device a pair of its choosing.
  Future<WrapsSync> syncWraps(String backupJson) async {
    final masterSeedB64 = state.masterSeed;
    if (masterSeedB64 == null) return WrapsSync.same;
    try {
      final backup = BackupFile.fromJsonString(backupJson);
      final vaultKey = await _crypto.deriveLocalVaultKey(
        CryptoRepository.fromBase64(masterSeedB64),
      );
      final theirs = await _openWraps(backup, vaultKey);
      final ours = await _storage.getWrapsAt();
      final theirsAt = theirs?.at ?? 0;
      if (theirsAt < ours) return WrapsSync.localNewer;
      if (theirs == null || theirsAt == ours) return WrapsSync.same;

      await _storage.saveEncryptedSeed(theirs.seed);
      if (theirs.recovery != null) {
        await _storage.saveRecoverySeed(theirs.recovery!);
      } else {
        await _storage.deleteRecoverySeed();
      }
      await _storage.saveSeedWrapEmail(theirs.email);
      await _storage.saveWrapsAt(theirsAt);
      // A key waiting to be written down here no longer opens anything:
      // the recovery wrap is the other device's now, and so is its key.
      if (state.pendingRecoveryKey != null) {
        await _storage.clearPendingRecoveryKey();
        emit(state.copyWith(clearPendingRecoveryKey: true));
      }
      return WrapsSync.adopted;
    } catch (e) {
      HelperMethods.printDebug('[Vault] syncWraps failed: $e');
      return WrapsSync.same;
    }
  }

  /// Whether [recoveryKey] opens [backupJson]'s recovery wrap, checked in
  /// memory with nothing written: null when it does, else what to say.
  Future<String?> opensWithRecoveryKey({
    required String backupJson,
    required String recoveryKey,
  }) async {
    try {
      final blob = BackupFile.fromJsonString(backupJson).recovery;
      if (blob == null) return 'This backup has no recovery key on it';
      final opened = await unwrapWithRecoveryKey(
        blob: blob,
        recoveryKey: recoveryKey,
      );
      return opened.masterSeedB64 == null
          ? (opened.error ?? 'That recovery key does not match')
          : null;
    } catch (e) {
      HelperMethods.printDebug('[Vault] opensWithRecoveryKey: $e');
      return 'The backup on this account is damaged.';
    }
  }

  /// [password] tried on [blob]: the seed, or null when it does not open.
  Future<String?> _openSeed(EncryptedSeed blob, String password) async {
    final key = await _crypto.deriveVaultKey(
      password: password,
      salt: CryptoRepository.fromBase64(blob.salt),
    );
    try {
      return await _crypto.decrypt(
        ciphertext: CryptoRepository.fromBase64(blob.ciphertext),
        key: key,
        iv: CryptoRepository.fromBase64(blob.iv),
      );
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  /// Restores a vault from a [BackupFile] JSON string.
  ///
  /// Opened with [password], or with [recoveryKey] when the password is the
  /// thing that was lost. They are alternatives, not a fallback chain: the two
  /// blobs wrap the same seed under unrelated keys, so trying both would only
  /// mean reporting the wrong one as wrong.
  ///
  /// [accountEmail] names the account a backup may have been made on. A seed
  /// on an account is wrapped under the password derived for that account,
  /// not the one typed, so [password] is tried both ways: typed, then derived.
  /// Without it a file exported on an account opened only with the recovery
  /// key.
  ///
  /// Everything is opened and checked before anything is written, and what
  /// is written goes as one record (`SecureStorageRepository.replaceVault`):
  /// a failure part-way used to leave the new seed beside the old vault's
  /// wraps, reported as a failed restore.
  ///
  /// On success emits [AuthStatus.unlocked] and fully populates secure storage.
  Future<({bool success, String? error})> importBackup({
    required String jsonContent,
    String? password,
    String? recoveryKey,
    String? accountEmail,
  }) async {
    assert(
      (password == null) != (recoveryKey == null),
      'importBackup takes a password or a recovery key, not both and not neither',
    );
    emit(state.copyWith(isProcessing: true, clearError: true));

    ({bool success, String? error}) fail(String msg) {
      emit(state.copyWith(isProcessing: false, error: msg));
      return (success: false, error: msg);
    }

    try {
      final backup = BackupFile.fromJsonString(jsonContent);
      if (backup.version > BackupFile.currentVersion) {
        return fail(
          'This backup was made by a newer version of Rift. Update Rift, '
          'then restore it.',
        );
      }

      String? masterSeedB64;
      String? wrapEmail;
      if (recoveryKey != null) {
        final blob = backup.recovery;
        if (blob == null) return fail('This backup has no recovery key on it');
        final unwrapped = await unwrapWithRecoveryKey(
          blob: blob,
          recoveryKey: recoveryKey,
        );
        if (unwrapped.masterSeedB64 == null) {
          return fail(unwrapped.error ?? 'That recovery key does not match');
        }
        masterSeedB64 = unwrapped.masterSeedB64!;
      } else {
        masterSeedB64 = await _openSeed(backup.seed, password!);
        final email = accountEmail?.trim();
        if (masterSeedB64 == null && email != null && email.isNotEmpty) {
          final derived = await _crypto.deriveAccountKeys(
            email: email,
            password: password,
          );
          masterSeedB64 = await _openSeed(backup.seed, derived.vaultPassword);
          if (masterSeedB64 != null) wrapEmail = email;
        }
        if (masterSeedB64 == null) {
          return fail('Wrong password or corrupted backup');
        }
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

      // The server list too, before anything is written.
      final ServerManifest manifest;
      if (backup.encryptedServers != null) {
        final serversJson = await _crypto.decrypt(
          ciphertext: CryptoRepository.fromBase64(
            backup.encryptedServers!.ciphertext,
          ),
          key: vaultKey,
          iv: CryptoRepository.fromBase64(backup.encryptedServers!.iv),
        );
        manifest = ServerManifest.decode(jsonDecode(serversJson));
      } else {
        // Legacy v1 backup — fall back to url/version stubs from vault blob.
        manifest = ServerManifest(
          servers: joinedServers
              .map(
                (s) => <String, dynamic>{
                  'supabaseUrl': s.url,
                  'keyVersion': s.version,
                },
              )
              .toList(),
        );
      }

      // The clock and the account travel only in the sealed wraps, and count
      // only when they describe the very wraps being restored.
      final sealed = await _openWraps(backup, vaultKey);
      final sealedMatches =
          sealed != null &&
          sealed.seed == backup.seed &&
          sealed.recovery == backup.recovery;
      if (recoveryKey != null && sealedMatches) wrapEmail = sealed.email;

      final previous = await _storage.getMasterSeed();
      try {
        await _storage.replaceVault(
          StoredVault(
            masterSeed: masterSeedB64,
            joinedServers: joinedServers,
            seed: backup.seed,
            vault: backup.vault,
            // A backup without one leaves none: the old vault's wrap would go
            // out with this identity's next backup, opening nothing.
            recovery: backup.recovery,
            // A key shown here belonged to the vault being replaced.
            pendingRecoveryKey: null,
            wrapsAt: sealedMatches ? sealed.at : 0,
            seedWrapEmail: wrapEmail,
          ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Vault] importBackup could not save: $e');
        return fail('Could not save the restored vault on this device.');
      }

      if (previous != null && previous != masterSeedB64) {
        // Another identity: what this device kept of the old one goes.
        await _forgetIdentity();
      } else {
        // Both caches hold what the seed derived. Only the signing one was
        // emptied once, so after a cloud backup was restored over this
        // device's vault every chat key was still the old vault's until the
        // app restarted.
        _identityCache.clear();
        _chatIdentityCache.clear();
      }
      // After the forgetting, which retires the seed it wipes: a reset and
      // then this same backup would otherwise leave it saving nothing.
      MessageCache.instance.adopt(masterSeedB64);

      emit(VaultState(status: AuthStatus.unlocked, masterSeed: masterSeedB64));
      _onServersImported?.call(manifest);

      return (success: true, error: null);
    } on SecretBoxAuthenticationError {
      // AES-GCM MAC check failed on the vault — a corrupted backup.
      const msg = 'Wrong password or corrupted backup';
      HelperMethods.printDebug('[Vault] importBackup: $msg');
      return fail(msg);
    } catch (e) {
      // Not only exceptions: a file that is JSON but not a backup throws a
      // TypeError, and a short ciphertext a RangeError. Caught as Exception
      // alone, either left the spinner running until the app restarted.
      HelperMethods.printDebug('[Vault] importBackup error: $e');
      return fail('That file is not a Rift backup, or it is damaged.');
    }
  }
}
