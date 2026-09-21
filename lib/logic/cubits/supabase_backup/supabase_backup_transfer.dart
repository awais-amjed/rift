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
  bool Function(ServerManifest)? get _mergeCloudServers;

  /// Implemented by the cubit.
  Future<void> _uploadBackup({required String successMessage});

  /// Manual "save to cloud" action from settings.
  ///
  /// Combines first, like the automatic one. This is "back this device up
  /// now", not "make the cloud look like this device" — the second of those
  /// is the conflict resolver, and it is the only thing that overwrites.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    await pullFromCloud();
    await _uploadBackup(successMessage: 'Backup saved to cloud successfully.');
  }

  /// Debounced, silent backup upload — called whenever the vault or server
  /// list changes. No-op when signed out or the vault is locked.
  void autoBackup() {
    if (!state.isSignedIn) return;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return;

    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(_autoBackupDebounce, () async {
      // Read before write. The upload is an upsert of one object, so without
      // this a device writes its own list over whatever the other one put
      // there — and a server joined on a phone lasts until the laptop's next
      // backup. See [BackupMerge] for what "combine" means here.
      await pullFromCloud();

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

  /// Folds the cloud's server list into this device's.
  ///
  /// Returns true when the rail changed. Silent about failure on purpose:
  /// offline, or a backup this seed cannot open, both mean "carry on with
  /// what is here" rather than "stop".
  ///
  /// It cannot converge on its own. Nothing serialises the read against the
  /// write — Storage has no compare-and-swap — so two devices merging inside
  /// the same second still resolve to whichever uploads last. That window is
  /// about a second, the cost of losing it is an order nobody chose, and the
  /// next reorder settles it. Closing it properly means moving the vault out
  /// of a bucket and into a row, where Postgres can refuse the second write.
  Future<bool> pullFromCloud() async {
    if (!state.isSignedIn) return false;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return false;
    final merge = _mergeCloudServers;
    if (merge == null) return false;

    final response = await _repo.downloadBackup();
    if (!response.success) return false;
    final backupJson = response.data as String?;
    if (backupJson == null) return false;

    final theirs = await _vaultCubit.readServerManifest(backupJson);
    if (theirs == null) return false;
    return merge(theirs);
  }

  void clearMessage() =>
      emit(state.copyWith(clearMessage: true, needsEmailConfirmation: false));

  // ──────────────────────────────────────────────────────────
  // Helpers
}
