part of 'supabase_backup_cubit.dart';

/// Changing the password, on an account or on a local-only vault.
///
/// One typed password stands behind two separate things (ARCHITECTURE.md §3):
/// the verifier GoTrue stores, and the key that wraps the master seed. Changing
/// it means changing both, and the whole difficulty of this file is that they
/// can fail independently.
///
/// The order below is chosen so they cannot end up disagreeing:
///
///   1. re-wrap the seed locally — reversible, nothing has left the device;
///   2. tell GoTrue the new verifier;
///   3. if that fails, put the seed back the way it was;
///   4. only then upload.
///
/// Doing it the other way round would leave the failure case as an account
/// whose password no longer opens its own backup, which is indistinguishable
/// from data loss and is not something the person could fix.
mixin _SupabaseBackupPasswordMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  CryptoRepository get _crypto;
  VaultCubit get _vaultCubit;

  String? get _pendingOldVaultPassword;
  set _pendingOldVaultPassword(String? value);

  Future<void> _uploadBackup({required String successMessage});

  /// The vault-blob password for [typed], which is not always [typed].
  ///
  /// On an account it is `KDF(typed, "vault")`, so the server never sees
  /// anything that opens the backup. In privacy mode there is no account and
  /// no email to salt with, and the typed password guards the seed directly.
  Future<String> _vaultPasswordFor(String typed) async {
    final email = state.email;
    if (!state.isSignedIn || email == null) return typed;
    final keys = await _crypto.deriveAccountKeys(email: email, password: typed);
    return keys.vaultPassword;
  }

  /// Step one: prove the current password, then ask for a code if there is an
  /// address to send one to.
  ///
  /// The password is checked against the local seed blob rather than by trying
  /// to sign in, for two reasons: it is the blob that actually has to open
  /// afterwards, and a wrong guess costs nothing but a second of Argon2id —
  /// no email, no rate limit spent, nothing to undo.
  Future<void> beginPasswordChange({required String currentPassword}) async {
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final oldVaultPassword = await _vaultPasswordFor(currentPassword);
    final ok = await _vaultCubit.verifyVaultPassword(oldVaultPassword);
    if (!ok) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: 'That is not your current password.',
        ),
      );
      return;
    }

    _pendingOldVaultPassword = oldVaultPassword;

    // Privacy mode: no account, no address, nothing to email. The typed
    // password was the only thing guarding the seed and it has just been
    // proved, so there is no second factor to wait for.
    if (!state.isSignedIn) {
      emit(
        state.copyWith(
          isProcessing: false,
          passwordChange: PasswordChangeStage.enterNew,
        ),
      );
      return;
    }

    final sent = await _repo.sendReauthenticationCode();
    if (!sent.success) {
      _pendingOldVaultPassword = null;
      emit(state.copyWith(isProcessing: false, error: sent.error));
      return;
    }

    emit(
      state.copyWith(
        isProcessing: false,
        passwordChange: PasswordChangeStage.enterCode,
        successMessage: 'We sent a code to ${state.email}. Enter it to finish.',
      ),
    );
  }

  /// Step two: set the new password everywhere it is used.
  ///
  /// [code] is the emailed nonce, required for an account and meaningless
  /// without one.
  Future<void> submitPasswordChange({
    required String newPassword,
    String? code,
  }) async {
    final oldVaultPassword = _pendingOldVaultPassword;
    if (oldVaultPassword == null) {
      emit(
        state.copyWith(
          isProcessing: false,
          error: 'Start again — the current password was not confirmed.',
          passwordChange: PasswordChangeStage.idle,
        ),
      );
      return;
    }

    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final newVaultPassword = await _vaultPasswordFor(newPassword);

    // 1. Local first: re-wrap the seed under the new password.
    final rewrapped = await _vaultCubit.changeVaultPassword(
      oldPassword: oldVaultPassword,
      newPassword: newVaultPassword,
    );
    if (!rewrapped.success) {
      emit(state.copyWith(isProcessing: false, error: rewrapped.error));
      return;
    }

    if (state.isSignedIn) {
      final email = state.email!;
      final keys = await _crypto.deriveAccountKeys(
        email: email,
        password: newPassword,
      );
      final updated = await _repo.updatePassword(
        password: keys.authPassword,
        nonce: code ?? '',
      );

      if (!updated.success) {
        // 3. Put the seed back. Without this the account password and the
        // blob that has to open with it would have drifted apart, and the
        // person would be left signing in fine and unable to read anything.
        await _vaultCubit.changeVaultPassword(
          oldPassword: newVaultPassword,
          newPassword: oldVaultPassword,
        );
        emit(state.copyWith(isProcessing: false, error: updated.error));
        return;
      }

      _accountVaultPassword = newVaultPassword;
    }

    _pendingOldVaultPassword = null;
    emit(state.copyWith(passwordChange: PasswordChangeStage.idle));

    // 4. The stored backup still holds the old seed blob. Until this lands,
    // a restore on another device would want the old password.
    if (state.isSignedIn) {
      await _uploadBackup(successMessage: 'Password changed.');
      return;
    }
    emit(
      state.copyWith(isProcessing: false, successMessage: 'Password changed.'),
    );
  }

  /// Mint a new recovery key, retiring the old one.
  ///
  /// **Goes through here rather than straight to [VaultCubit] because of the
  /// derivation.** The seed blob on an account is wrapped under
  /// `KDF(typed, "vault")`, not under what the person types — so a panel that
  /// handed the raw string to the vault would be told "wrong password" by an
  /// account holder who typed exactly the right one.
  Future<({bool success, String? error})> replaceRecoveryKey({
    required String password,
  }) async {
    final vaultPassword = await _vaultPasswordFor(password);
    final result = await _vaultCubit.regenerateRecoveryKey(
      password: vaultPassword,
    );
    if (!result.success) {
      return (success: false, error: result.error);
    }

    // The stored backup still carries the old wrap, and a recovery key that
    // only works against this device is not a recovery key.
    if (state.isSignedIn) {
      await _uploadBackup(successMessage: 'Recovery key replaced.');
    }
    return (success: true, error: null);
  }

  /// Abandon a change in progress, forgetting the proved password with it.
  void cancelPasswordChange() {
    _pendingOldVaultPassword = null;
    emit(
      state.copyWith(
        passwordChange: PasswordChangeStage.idle,
        clearMessage: true,
      ),
    );
  }

  /// Set by [submitPasswordChange] so later uploads use the new derivation.
  set _accountVaultPassword(String? value);
}
