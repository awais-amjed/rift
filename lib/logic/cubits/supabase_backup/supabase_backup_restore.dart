part of 'supabase_backup_cubit.dart';

/// Restoring a cloud backup into the vault: the silent path, the manual
/// vault-password prompt, and the two conflict resolvers.
mixin _SupabaseBackupRestoreMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  VaultCubit get _vaultCubit;
  String? get _accountVaultPassword;
  String? get _pendingCloudBackup;
  set _pendingCloudBackup(String? value);

  /// Implemented by the cubit and the transfer mixin respectively.
  Future<void> _uploadBackup({required String successMessage});
  void autoBackup();

  /// Downloads the cloud backup and imports it into the vault.
  ///
  /// Uses the derived account password when available; [vaultPassword]
  /// overrides it (manual restore of a privacy-mode backup).
  Future<void> importBackupFromCloud({String? vaultPassword}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final downloadResponse = await _repo.downloadBackup();
    if (!downloadResponse.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] downloadBackup failed: ${downloadResponse.error}',
      );
      emit(state.copyWith(isProcessing: false, error: downloadResponse.error));
      return;
    }

    final backupJson = downloadResponse.data as String?;
    if (backupJson == null) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: 'No backup found on server.',
        ),
      );
      return;
    }

    if (vaultPassword != null) {
      _pendingCloudBackup = backupJson;
      await submitVaultPassword(vaultPassword);
    } else {
      await _importPendingBackup(backupJson);
    }
  }

  /// Imports [backupJson], trying the derived account password first and
  /// falling back to a user prompt when the backup was encrypted with a
  /// manually chosen vault password (privacy-mode export).
  Future<void> _importPendingBackup(String backupJson) async {
    final derived = _accountVaultPassword;
    if (derived != null) {
      final result = await _vaultCubit.importBackup(
        jsonContent: backupJson,
        password: derived,
      );
      if (result.success) {
        _pendingCloudBackup = null;
        emit(
          state.copyWith(
            isProcessing: false,
            successMessage: 'Backup restored from your account.',
          ),
        );
        return;
      }
    }

    _pendingCloudBackup = backupJson;
    emit(state.copyWith(isProcessing: false, needsVaultPassword: true));
  }

  /// Completes a pending import with a manually entered vault password.
  Future<void> submitVaultPassword(String vaultPassword) async {
    final backupJson = _pendingCloudBackup;
    if (backupJson == null) return;

    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final result = await _vaultCubit.importBackup(
      jsonContent: backupJson,
      password: vaultPassword,
    );
    if (result.success) {
      _pendingCloudBackup = null;
      emit(
        state.copyWith(
          isProcessing: false,
          needsVaultPassword: false,
          successMessage: 'Backup restored from your account.',
        ),
      );
      // Re-encrypt under the derived password so future restores are silent.
      await _reencryptUnderAccountPassword(vaultPassword);
    } else {
      emit(
        state.copyWith(
          isProcessing: false,
          error: result.error ?? 'Failed to import backup.',
        ),
      );
    }
  }

  /// Conflict resolver: keep the local vault, overwriting the cloud backup.
  Future<void> keepLocalVault() async {
    _pendingCloudBackup = null;
    emit(
      state.copyWith(
        isProcessing: true,
        cloudBackupConflict: false,
        clearMessage: true,
      ),
    );
    await _uploadBackup(
      successMessage: 'Cloud backup replaced with this device\'s vault.',
    );
  }

  /// Conflict resolver: restore the cloud backup, replacing the local vault.
  Future<void> restoreCloudBackup() async {
    final backupJson = _pendingCloudBackup;
    if (backupJson == null) return;
    emit(
      state.copyWith(
        isProcessing: true,
        cloudBackupConflict: false,
        clearMessage: true,
      ),
    );
    await _importPendingBackup(backupJson);
  }

  /// Dismisses pending prompts without acting (e.g. user backed out).
  void dismissPending() {
    _pendingCloudBackup = null;
    emit(
      state.copyWith(
        needsVaultPassword: false,
        cloudBackupConflict: false,
        clearMessage: true,
      ),
    );
  }

  /// After importing a privacy-mode backup with a manual password, re-encrypt
  /// the seed under the derived account password and re-upload, so future
  /// sign-ins on fresh devices restore without a prompt.
  Future<void> _reencryptUnderAccountPassword(String oldPassword) async {
    final derived = _accountVaultPassword;
    if (derived == null) return;

    final result = await _vaultCubit.changeVaultPassword(
      oldPassword: oldPassword,
      newPassword: derived,
    );
    if (!result.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] re-encrypt after import failed: ${result.error}',
      );
      return;
    }
    autoBackup();
  }
}
