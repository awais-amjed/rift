part of 'supabase_backup_cubit.dart';

/// Pushing the vault to the cloud: the manual save and the debounced
/// automatic one that follows every vault or server-list change.
mixin _SupabaseBackupTransferMixin on Cubit<SupabaseBackupState> {
  /// Long enough that a burst of vault edits uploads once.
  static const _autoBackupDebounce = Duration(seconds: 3);

  SupabaseBackupRepository get _repo;
  VaultCubit get _vaultCubit;
  Timer? get _autoBackupTimer;
  set _autoBackupTimer(Timer? value);

  /// Implemented by the cubit.
  Future<void> _uploadBackup({required String successMessage});

  /// Manual "save to cloud" action from settings.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    await _uploadBackup(successMessage: 'Backup saved to cloud successfully.');
  }

  /// Debounced, silent backup upload — called whenever the vault or server
  /// list changes. No-op when signed out or the vault is locked.
  void autoBackup() {
    if (!state.isSignedIn) return;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return;

    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(_autoBackupDebounce, () async {
      final export = await _vaultCubit.exportBackup();
      if (!export.success || export.content == null) {
        HelperMethods.printDebug(
          '[SupabaseBackup] autoBackup export failed: ${export.error}',
        );
        return;
      }
      final response = await _repo.uploadBackup(export.content!);
      if (!response.success) {
        HelperMethods.printDebug(
          '[SupabaseBackup] autoBackup upload failed: ${response.error}',
        );
      }
    });
  }

  void clearMessage() =>
      emit(state.copyWith(clearMessage: true, needsEmailConfirmation: false));

  // ──────────────────────────────────────────────────────────
  // Helpers
}
