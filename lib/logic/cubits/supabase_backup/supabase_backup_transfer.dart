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
  bool get _wrapChangeInFlight;
  CloudMerge Function(ServerManifest)? get _mergeCloudServers;

  /// Implemented by the cubit.
  Future<bool> _uploadBackup({required String successMessage});
  void _raiseConflict(String backupJson);

  /// Manual "save to cloud" action from settings.
  ///
  /// Combines first, like the automatic one. This is "back this device up
  /// now", not "make the cloud look like this device" — the second of those
  /// is the conflict resolver, and it is the only thing that overwrites.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final pulled = await _pull();
    if (pulled.copy == _CloudCopy.other) return;
    await _uploadBackup(successMessage: 'Backup saved to cloud successfully.');
  }

  /// Debounced, silent backup upload — called whenever the vault or server
  /// list changes. No-op when signed out or the vault is locked.
  void autoBackup() {
    if (!state.isSignedIn) return;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return;

    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(_autoBackupDebounce, () async {
      // A password change is between its two halves; back up after it.
      if (_wrapChangeInFlight) {
        autoBackup();
        return;
      }
      // Read before write. The upload is an upsert of one object, so without
      // this a device writes its own list over whatever the other one put
      // there — and a server joined on a phone lasts until the laptop's next
      // backup. See [BackupMerge] for what "combine" means here. And it is
      // what keeps this upload off another identity's backup: that is never
      // overwritten except by the person choosing to.
      final pulled = await _pull();
      if (pulled.copy != _CloudCopy.ours && pulled.copy != _CloudCopy.none) {
        return;
      }

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
  /// offline means "carry on with what is here" rather than "stop". A backup
  /// of another identity is the exception: it is said, and backing up stops
  /// until the person chooses ([_raiseConflict]) — after a restart this is
  /// what asks again.
  ///
  /// [thenPush] also sends what this device knows *back*, when the cloud is
  /// behind: an older server list, older wraps, or no backup at all. That is
  /// the only thing that rescues a change made with no network: the upload it
  /// scheduled failed once and nothing retried it, so the change sat on the
  /// device it was made on until some unrelated edit happened to trigger
  /// another backup. Coming back to the app is now a retry. [autoBackup]
  /// pulls without it — the push is the next thing that function does
  /// anyway, and asking for one there is an endless loop.
  ///
  /// It still cannot converge in one hop. Nothing serialises the read against
  /// the write — Storage has no compare-and-swap — so two devices merging
  /// inside the same second resolve to whichever uploads last. That window is
  /// about a second, the cost of losing it is an order nobody chose, and the
  /// next reorder settles it. Closing it properly means moving the vault out
  /// of a bucket and into a row, where Postgres can refuse the second write.
  Future<bool> pullFromCloud({bool thenPush = false}) async {
    final pulled = await _pull();
    if (thenPush && pulled.cloudStale) autoBackup();
    return pulled.railChanged;
  }

  Future<({_CloudCopy copy, bool railChanged, bool cloudStale})> _pull() async {
    const skipped = (
      copy: _CloudCopy.unknown,
      railChanged: false,
      cloudStale: false,
    );
    if (!state.isSignedIn) return skipped;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return skipped;
    final merge = _mergeCloudServers;
    if (merge == null) return skipped;

    final response = await _repo.downloadBackup();
    if (!response.success) return skipped;
    final backupJson = response.data as String?;
    if (backupJson == null) {
      // Nothing there: a first upload that failed was never tried again.
      return (copy: _CloudCopy.none, railChanged: false, cloudStale: true);
    }
    if (!await _vaultCubit.isBackupOfThisVault(backupJson)) {
      _raiseConflict(backupJson);
      return (copy: _CloudCopy.other, railChanged: false, cloudStale: false);
    }

    final wraps = await _vaultCubit.syncWraps(backupJson);
    final wrapsStale = wraps == WrapsSync.localNewer;
    final theirs = await _vaultCubit.readServerManifest(backupJson);
    if (theirs == null) {
      return (
        copy: _CloudCopy.ours,
        railChanged: false,
        cloudStale: wrapsStale,
      );
    }

    final outcome = merge(theirs);
    if (outcome.joined.isNotEmpty) {
      // One at a time: each is a read and a write of the same stored list,
      // and run together they lost each other's hosts.
      unawaited(() async {
        for (final host in outcome.joined) {
          await _vaultCubit.noteJoinedHost(host.url, version: host.version);
        }
      }());
    }
    return (
      copy: _CloudCopy.ours,
      railChanged: outcome.railChanged,
      cloudStale: outcome.cloudStale || wrapsStale,
    );
  }

  void clearMessage() =>
      emit(state.copyWith(clearMessage: true, needsEmailConfirmation: false));
}

/// What [_SupabaseBackupTransferMixin._pull] found in the cloud.
enum _CloudCopy {
  /// Not looked at: signed out, locked, or the account unreachable.
  unknown,

  /// No backup on the account yet.
  none,

  /// A backup of this vault.
  ours,

  /// A backup of another identity.
  other,
}
