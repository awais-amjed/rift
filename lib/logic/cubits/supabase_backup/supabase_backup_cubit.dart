import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import '../../../data/classes/api_response.dart';
import '../../../data/classes/notice.dart';
import '../../../data/enums/auth_status.dart';
import '../../../data/enums/error_code.dart';
import '../../../data/repositories/central_dm_repository.dart';
import '../../../data/repositories/supabase_backup_repository.dart';
import '../../../logic/helper_methods.dart';
import '../../services/backup_merge.dart';
import '../../services/central_handle.dart';
import '../../services/push_service.dart';
import '../../services/window_focus_service.dart';
import '../vault/vault_cubit.dart';

part 'supabase_backup_account_recovery.dart';
part 'supabase_backup_auth.dart';
part 'supabase_backup_delete.dart';
part 'supabase_backup_password.dart';
part 'supabase_backup_password_reset.dart';
part 'supabase_backup_restore.dart';
part 'supabase_backup_state.dart';
part 'supabase_backup_transfer.dart';

/// Manages the central-server account and cloud backup sync.
///
/// Auth follows the Option B split-key scheme (ARCHITECTURE.md §3): the
/// password the user types never leaves the device. One derivation yields
/// the auth verifier sent to Supabase and the vault password used for the
/// client-side backup encryption.
///
/// After a successful sign-in/up, [_postAuthSync] reconciles local vault and
/// cloud backup automatically:
/// - fresh device + cloud backup   → import silently (prompt only if the
///   backup was encrypted with a manually chosen vault password)
/// - fresh device + no backup      → create vault + upload
/// - local vault  + no backup      → upload (adopts the vault into the account)
/// - local vault  + its own backup → combine and upload, like any later sync
/// - local vault  + another backup → surface a conflict for the user to resolve
///
/// A device that arrives signed in with a vault of its own first re-wraps its
/// seed under the account password, if it was made under another one.
class SupabaseBackupCubit extends Cubit<SupabaseBackupState>
    with
        _SupabaseBackupAuthMixin,
        _SupabaseBackupDeleteMixin,
        _SupabaseBackupRestoreMixin,
        _SupabaseBackupTransferMixin,
        _SupabaseBackupPasswordMixin,
        _SupabaseBackupPasswordResetMixin,
        _SupabaseBackupAccountRecoveryMixin {
  /// How long the resend button stays locked after asking.
  ///
  /// Matched to the central project's `smtp_max_frequency`, which is 60
  /// seconds: the server would refuse a second request inside that window
  /// anyway, and being refused costs the same hourly allowance as being
  /// obeyed. Better to hold the button than to spend an email learning it was
  /// too soon.
  static const Duration resendCooldown = Duration(seconds: 60);

  @override
  final SupabaseBackupRepository _repo;

  /// Where this device's push registration lives, for signing out.
  @override
  final CentralDmRepository _devices;
  @override
  final CryptoRepository _crypto;
  @override
  final VaultCubit _vaultCubit;

  /// Derived vault password for the signed-in account (Option B).
  /// Memory-only — never persisted or transmitted. Null when signed out or
  /// when the session was restored from disk (re-derived on next sign-in).
  @override
  String? _accountVaultPassword;

  /// The vault-blob password proved during a change in progress.
  ///
  /// Memory-only and cleared the moment the change lands or is abandoned —
  /// it is a password-equivalent, and it exists only so the second step does
  /// not have to ask for the old password a second time.
  @override
  String? _pendingOldVaultPassword;

  /// Cloud backup JSON awaiting a user decision (password prompt / conflict).
  @override
  String? _pendingCloudBackup;

  @override
  Timer? _autoBackupTimer;

  /// Set while a password change or reset is between re-wrapping the seed
  /// here and GoTrue answering. An automatic backup waits it out: uploaded in
  /// that window, a wrap the account might yet refuse reached the cloud, and
  /// putting the old one back here did not put it back there.
  @override
  bool _wrapChangeInFlight = false;

  /// The address whose recovery code made the session account recovery is
  /// in, so a wrong recovery key can be tried again without a new code.
  @override
  String? _recoveryVerifiedFor;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<VaultState>? _vaultSub;

  /// Hands the cloud's server list to [ServerCubit] to be combined with this
  /// device's. Injected after construction, like every other cross-cubit
  /// dependency here, to keep the two from having to be built in an order.
  @override
  CloudMerge Function(ServerManifest)? _mergeCloudServers;

  void setMergeCloudServers(CloudMerge Function(ServerManifest) merge) {
    _mergeCloudServers = merge;
  }

  /// Whether the once-per-launch pull has happened.
  bool _openedPull = false;

  /// The last time [pullFromCloud] ran for a window regaining focus.
  ///
  /// Alt-tabbing is not a sync request. Without a floor, a person moving
  /// between two windows downloads the vault on every pass.
  DateTime? _lastFocusPull;

  /// How long after a pull another focus is ignored.
  static const Duration focusPullInterval = Duration(minutes: 2);

  /// Set while the user intentionally signs out, so the auth-change listener
  /// doesn't mistake it for the session being lost server-side.
  bool _intentionalSignOut = false;

  SupabaseBackupCubit({
    required VaultCubit vaultCubit,
    SupabaseBackupRepository? repo,
    CentralDmRepository? devices,
    CryptoRepository? crypto,
  }) : _repo = repo ?? SupabaseBackupRepository(),
       _devices = devices ?? CentralDmRepository(),
       _crypto = crypto ?? CryptoRepository(),
       _vaultCubit = vaultCubit,
       super(const SupabaseBackupState()) {
    // Reflect any persisted session restored by supabase_flutter on startup.
    final user = _repo.currentUser;
    if (user != null) {
      emit(SupabaseBackupState(isSignedIn: true, email: user.email));
    }
    // React to the session going away later — e.g. the account was deleted
    // server-side and the token can no longer be refreshed.
    _authSub = _repo.authChanges.listen(_onAuthChange);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    // A cold start with a session already on disk never changes focus and
    // never signs in, so neither of the other two triggers fires. What it
    // does do is unlock the vault, which is also the first moment a pull
    // could succeed.
    _vaultSub = _vaultCubit.stream.listen(_onVaultStateChanged);
  }

  void _onVaultStateChanged(VaultState vault) {
    if (isClosed || _openedPull) return;
    if (vault.status != AuthStatus.unlocked || !state.isSignedIn) return;
    _openedPull = true;
    _lastFocusPull = DateTime.now();
    unawaited(pullFromCloud(thenPush: true));
  }

  /// Coming back to the window is when a device should notice that the other
  /// one moved something. There is nothing to push a change here — the vault
  /// is an object in a bucket, and a bucket has nothing to subscribe to.
  void _onFocusChanged() {
    if (isClosed || !WindowFocusService.instance.isFocused) return;
    final last = _lastFocusPull;
    final now = DateTime.now();
    if (last != null && now.difference(last) < focusPullInterval) return;
    _lastFocusPull = now;
    unawaited(pullFromCloud(thenPush: true));
  }

  /// Reconcile signed-in state with GoTrue's session. When the session is lost
  /// unexpectedly (deleted account / unrecoverable expiry) we drop to guest —
  /// the local vault + servers are untouched, since the central account is
  /// optional — and tell the user so they're not silently stuck.
  void _onAuthChange(AuthState authState) {
    if (isClosed) return;
    final signedIn = authState.session != null;

    if (signedIn) {
      if (!state.isSignedIn) {
        emit(
          state.copyWith(
            isSignedIn: true,
            email: authState.session?.user.email,
          ),
        );
      }
      return;
    }

    // Session gone. Ignore our own explicit sign-out (handled in signOut()).
    if (_intentionalSignOut) {
      _intentionalSignOut = false;
      return;
    }
    if (state.isSignedIn) {
      _accountVaultPassword = null;
      _pendingCloudBackup = null;
      emit(
        state.copyWith(
          isSignedIn: false,
          email: null,
          notice: Notice.info(
            'Signed out',
            'Your cloud account session ended. Sign in again from Settings '
                'to resume backups.',
          ),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _autoBackupTimer?.cancel();
    _authSub?.cancel();
    _vaultSub?.cancel();
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    return super.close();
  }

  // ── Post-auth reconciliation ──────────────────────────────

  /// Decides what a fresh session means for this device: import, create,
  /// upload, or surface a conflict. The four outcomes are spelled out in the
  /// class doc above.
  @override
  Future<void> _postAuthSync() async {
    emit(state.copyWith(isProcessing: true));

    final downloadResponse = await _repo.downloadBackup();
    if (!downloadResponse.success) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: downloadResponse.error ?? 'Failed to check for cloud backup.',
        ),
      );
      return;
    }

    final backupJson = downloadResponse.data as String?;
    final vaultUnlocked = _vaultCubit.state.status == AuthStatus.unlocked;

    if (backupJson != null) {
      if (!vaultUnlocked) {
        await _importPendingBackup(backupJson);
      } else if (await _vaultCubit.isBackupOfThisVault(backupJson)) {
        // This identity's own backup — from here, or another device holding
        // the same seed. Nothing to choose between: combined and uploaded the
        // way every later backup is.
        await _wrapSeedUnderAccount();
        await pullFromCloud();
        await _uploadBackup(successMessage: 'Account connected. Backup saved.');
      } else {
        // Two different identities: the user must choose (see resolvers).
        // Nothing is re-wrapped until they have: this vault's own password
        // stopped opening it here the moment the account's was put on it,
        // whichever they went on to keep.
        _raiseConflict(backupJson, tell: false);
      }
      return;
    }

    // No cloud backup yet.
    if (!vaultUnlocked) {
      // Brand-new user: create the vault with the derived password so the
      // account password is the only password they ever have.
      await _vaultCubit.createVault(
        _accountVaultPassword!,
        accountEmail: state.email,
      );
      if (_vaultCubit.state.status != AuthStatus.unlocked) {
        emit(
          state.copyWith(
            isProcessing: false,
            error: _vaultCubit.state.error ?? 'Failed to create vault.',
          ),
        );
        return;
      }
    } else {
      await _wrapSeedUnderAccount();
    }
    await _uploadBackup(successMessage: 'Account connected. Backup saved.');
  }

  /// On an account the seed is wrapped by the account password (ARCHITECTURE.md
  /// §3) — that is what lets a new device restore with nothing else typed.
  /// A vault made in privacy mode and signed in later still had the password
  /// it was made with, so each upload from it put a blob in the cloud that the
  /// account could not open: the next restore asked for the old password, and
  /// re-wrapping it there lasted only until this device uploaded again.
  ///
  /// The seed is in memory, so nothing has to be proved first. The check
  /// costs one Argon2id run per sign-in, and the re-wrap a second, once.
  @override
  Future<void> _wrapSeedUnderAccount() async {
    final derived = _accountVaultPassword;
    final email = state.email;
    if (derived == null || email == null) return;
    if (await _vaultCubit.verifyVaultPassword(derived)) {
      // Wrapped for the account before that was recorded.
      if (await _vaultCubit.seedWrapEmail() != email) {
        await _vaultCubit.noteSeedWrapEmail(email);
      }
      return;
    }
    final result = await _vaultCubit.rewrapSeed(
      newPassword: derived,
      wrapEmail: email,
    );
    if (!result.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] re-wrap under the account failed: ${result.error}',
      );
    }
  }

  // ── Shared internals ──────────────────────────────────────

  /// Puts this device's vault in the cloud. True when it got there.
  ///
  /// Looks first, unless [_replaceCloudBackup] — the one answer to a conflict that is
  /// meant to overwrite. A backup of another identity is never replaced by
  /// anything else: it raises the conflict again. It used to be replaced by
  /// whatever upload came next — a server joined before the question was
  /// answered, a restart that forgot it was asked, the vault made after a
  /// reset — and the other identity was gone. A backup of this one first
  /// lends this device any newer wraps it holds ([VaultCubit.syncWraps]), so
  /// this upload does not put old ones back.
  @override
  Future<bool> _uploadBackup({required String successMessage}) =>
      _upload(successMessage: successMessage, replaceCloud: false);

  /// The conflict's "keep this device": the one upload that does not look.
  @override
  Future<bool> _replaceCloudBackup({required String successMessage}) =>
      _upload(successMessage: successMessage, replaceCloud: true);

  Future<bool> _upload({
    required String successMessage,
    required bool replaceCloud,
  }) async {
    if (!replaceCloud) {
      final cloud = await _repo.downloadBackup();
      if (!cloud.success) {
        emit(
          state.copyWith(
            isProcessing: false,
            error:
                cloud.error ??
                "Couldn't reach your account to check its backup.",
          ),
        );
        return false;
      }
      final cloudJson = cloud.data as String?;
      if (cloudJson != null) {
        if (!await _vaultCubit.isBackupOfThisVault(cloudJson)) {
          _raiseConflict(cloudJson);
          return false;
        }
        await _vaultCubit.syncWraps(cloudJson);
      }
    }

    final export = await _vaultCubit.exportBackup();
    if (!export.success || export.content == null) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: export.error ?? 'Failed to export backup',
        ),
      );
      return false;
    }

    final response = await _repo.uploadBackup(export.content!);
    if (!response.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] uploadBackup failed: ${response.error}',
      );
      emit(state.copyWith(isProcessing: false, error: response.error));
      return false;
    }
    emit(state.copyWith(isProcessing: false, successMessage: successMessage));
    return true;
  }

  /// The account's backup is another identity's: hold it for the person to
  /// choose, and stop backing up until they have. [tell] puts up a notice,
  /// for when this is found away from the page that asks.
  @override
  void _raiseConflict(String backupJson, {bool tell = true}) {
    _pendingCloudBackup = backupJson;
    final already = state.cloudBackupConflict;
    emit(
      state.copyWith(
        isProcessing: false,
        cloudBackupConflict: true,
        notice: (tell && !already)
            ? Notice.info(
                'Backups paused',
                "Your account's cloud backup holds a different identity "
                    "from this device's. Choose which to keep in Settings, "
                    'under Account & backup.',
                duration: Notice.long,
              )
            : null,
      ),
    );
  }

  /// Makes sure the cloud holds this device's vault, before signing the
  /// device out wipes it. True only when a fresh download proves it.
  ///
  /// "Sign out of this device" promises that signing back in restores
  /// everything, and that is only true when the backup is this vault's. A
  /// first upload that failed, or a backup of another identity, made that
  /// promise false, and the wipe that followed lost the seed for good.
  Future<bool> confirmCloudHoldsVault() async {
    if (!state.isSignedIn) return false;
    if (_vaultCubit.state.status != AuthStatus.unlocked) return false;
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    await pullFromCloud();
    if (!await _uploadBackup(successMessage: 'Backup saved.')) return false;
    final check = await _repo.downloadBackup();
    final json = check.success ? check.data as String? : null;
    final held = json != null && await _vaultCubit.isBackupOfThisVault(json);
    emit(state.copyWith(isProcessing: false));
    return held;
  }
}
