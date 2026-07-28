import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import '../../../data/enums/auth_status.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../../data/repositories/supabase_backup_repository.dart';
import '../../../logic/helper_methods.dart';
import '../vault/vault_cubit.dart';

part 'supabase_backup_state.dart';

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
/// - local vault  + cloud backup   → surface a conflict for the user to resolve
class SupabaseBackupCubit extends Cubit<SupabaseBackupState> {
  final SupabaseBackupRepository _repo;
  final CryptoRepository _crypto;
  final VaultCubit _vaultCubit;

  /// Derived vault password for the signed-in account (Option B).
  /// Memory-only — never persisted or transmitted. Null when signed out or
  /// when the session was restored from disk (re-derived on next sign-in).
  String? _accountVaultPassword;

  /// Cloud backup JSON awaiting a user decision (password prompt / conflict).
  String? _pendingCloudBackup;

  Timer? _autoBackupTimer;
  static const _autoBackupDebounce = Duration(seconds: 3);

  StreamSubscription<AuthState>? _authSub;

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
      emit(state.copyWith(isSignedIn: false, email: null));
      HelperMethods.showNotificationToast(
        title: 'Signed out',
        description:
            'Your cloud account session ended. Sign in again from Settings '
            'to resume backups.',
      );
    }
  }

  @override
  Future<void> close() {
    _autoBackupTimer?.cancel();
    _authSub?.cancel();
    return super.close();
  }

  // ──────────────────────────────────────────────────────────
  // Auth
  // ──────────────────────────────────────────────────────────

  /// Creates a new account on the central server.
  ///
  /// If the server requires email confirmation the state transitions to
  /// [SupabaseBackupState.needsEmailConfirmation]; the sync then runs on the
  /// sign-in that follows confirmation.
  Future<void> signUp({required String email, required String password}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final keys = await _crypto.deriveAccountKeys(
      email: email,
      password: password,
    );

    final response = await _repo.signUp(
      email: email,
      password: keys.authPassword,
    );
    if (!response.success) {
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final needsConfirmation = data['needsConfirmation'] as bool;
    if (needsConfirmation) {
      emit(
        state.copyWith(
          isProcessing: false,
          needsEmailConfirmation: true,
          email: email,
        ),
      );
      return;
    }

    final user = data['user'] as User;
    _accountVaultPassword = keys.vaultPassword;
    emit(state.copyWith(isSignedIn: true, email: user.email));
    await _postAuthSync();
  }

  /// Signs in to the central server.
  Future<void> signIn({required String email, required String password}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final keys = await _crypto.deriveAccountKeys(
      email: email,
      password: password,
    );

    final response = await _repo.signIn(
      email: email,
      password: keys.authPassword,
    );
    if (!response.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] signIn failed: ${response.error}',
      );
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }

    final user = response.data as User;
    _accountVaultPassword = keys.vaultPassword;
    emit(
      state.copyWith(
        isSignedIn: true,
        needsEmailConfirmation: false,
        email: user.email,
      ),
    );
    await _postAuthSync();
  }

  /// Signs out of the central server. The local vault is untouched.
  Future<void> signOut() async {
    _intentionalSignOut = true;
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final response = await _repo.signOut();
    if (!response.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] signOut failed: ${response.error}',
      );
      emit(state.copyWith(isProcessing: false, error: response.error));
      return;
    }
    _accountVaultPassword = null;
    _pendingCloudBackup = null;
    _autoBackupTimer?.cancel();
    emit(const SupabaseBackupState());
  }

  // ──────────────────────────────────────────────────────────
  // Post-auth reconciliation
  // ──────────────────────────────────────────────────────────

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
      if (vaultUnlocked) {
        // Local vault + cloud backup: the user must choose (see resolvers).
        _pendingCloudBackup = backupJson;
        emit(state.copyWith(isProcessing: false, cloudBackupConflict: true));
      } else {
        await _importPendingBackup(backupJson);
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

  // ──────────────────────────────────────────────────────────
  // Backup
  // ──────────────────────────────────────────────────────────

  /// Manual "save to cloud" action from settings.
  Future<void> saveBackupToCloud() async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));
    await _uploadBackup(successMessage: 'Backup saved to cloud successfully.');
  }

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
  // ──────────────────────────────────────────────────────────

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
