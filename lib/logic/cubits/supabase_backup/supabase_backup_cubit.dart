import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import '../../../data/classes/notice.dart';
import '../../../data/enums/auth_status.dart';
import '../../../data/enums/error_code.dart';
import '../../../data/repositories/supabase_backup_repository.dart';
import '../../../logic/helper_methods.dart';
import '../../services/backup_merge.dart';
import '../../services/central_handle.dart';
import '../../services/window_focus_service.dart';
import '../vault/vault_cubit.dart';

part 'supabase_backup_account_recovery.dart';
part 'supabase_backup_auth.dart';
part 'supabase_backup_password.dart';
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
        _SupabaseBackupRestoreMixin,
        _SupabaseBackupTransferMixin,
        _SupabaseBackupPasswordMixin,
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
    CryptoRepository? crypto,
  }) : _repo = repo ?? SupabaseBackupRepository(),
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

    if (vaultUnlocked) await _wrapSeedUnderAccount();

    if (backupJson != null) {
      if (!vaultUnlocked) {
        await _importPendingBackup(backupJson);
      } else if (await _vaultCubit.isBackupOfThisVault(backupJson)) {
        // This identity's own backup — from here, or another device holding
        // the same seed. Nothing to choose between: combined and uploaded the
        // way every later backup is.
        await pullFromCloud();
        await _uploadBackup(successMessage: 'Account connected. Backup saved.');
      } else {
        // Two different identities: the user must choose (see resolvers).
        _pendingCloudBackup = backupJson;
        emit(state.copyWith(isProcessing: false, cloudBackupConflict: true));
      }
      return;
    }

    // No cloud backup yet.
    if (!vaultUnlocked) {
      // Brand-new user: create the vault with the derived password so the
      // account password is the only password they ever have.
      await _vaultCubit.createVault(_accountVaultPassword!);
      if (_vaultCubit.state.status != AuthStatus.unlocked) {
        emit(
          state.copyWith(
            isProcessing: false,
            error: _vaultCubit.state.error ?? 'Failed to create vault.',
          ),
        );
        return;
      }
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
  Future<void> _wrapSeedUnderAccount() async {
    final derived = _accountVaultPassword;
    if (derived == null) return;
    if (await _vaultCubit.verifyVaultPassword(derived)) return;
    final result = await _vaultCubit.rewrapSeed(newPassword: derived);
    if (!result.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] re-wrap under the account failed: ${result.error}',
      );
    }
  }

  // ── Shared internals ──────────────────────────────────────

  @override
  Future<void> _uploadBackup({required String successMessage}) async {
    final export = await _vaultCubit.exportBackup();
    if (!export.success || export.content == null) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: export.error ?? 'Failed to export backup',
        ),
      );
      return;
    }

    final response = await _repo.uploadBackup(export.content!);
    if (!response.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] uploadBackup failed: ${response.error}',
      );
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    emit(state.copyWith(isProcessing: false, successMessage: successMessage));
  }
}
