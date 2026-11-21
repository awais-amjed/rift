part of 'supabase_backup_cubit.dart';

/// A new password from a device signed in to the account, without the old one.
///
/// The old password guards the seed blob, and this device does not need the
/// blob: the seed is already unwrapped in memory. What is left to prove is the
/// inbox — the emailed code, which central's GoTrue checks before taking a new
/// password (`GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_REAUTHENTICATION`).
/// Someone holding the unlocked device can already read everything on it, so
/// the inbox is the gate that matters.
///
/// A new recovery key comes with it. Whoever forgot the password has likely
/// lost the key too, and once the password is gone that key is the only way
/// back should this device go. In privacy mode there is no account and no
/// address to ask, so this is not offered there.
///
/// Same order as [_SupabaseBackupPasswordMixin.submitPasswordChange]: re-wrap
/// locally, tell GoTrue, put the blob back if GoTrue refuses, then upload.
mixin _SupabaseBackupPasswordResetMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  CryptoRepository get _crypto;
  VaultCubit get _vaultCubit;

  set _accountVaultPassword(String? value);
  set _wrapChangeInFlight(bool value);

  Future<bool> _uploadBackup({required String successMessage});

  /// Implemented by [_SupabaseBackupPasswordMixin].
  Future<bool> _landedAnyway(
    APIResponse updated,
    String email,
    String authPassword,
  );

  /// Step one: email a code to the address on the account.
  Future<void> beginPasswordReset() async {
    if (!state.isSignedIn) return;
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final sent = await _repo.sendReauthenticationCode();
    if (!sent.success) {
      emit(state.copyWith(isProcessing: false, error: sent.error));
      return;
    }

    emit(
      state.copyWith(
        isProcessing: false,
        passwordChange: PasswordChangeStage.reset,
        successMessage: 'We sent a code to ${state.email}. Enter it to finish.',
      ),
    );
  }

  /// Step two: the code and the new password.
  Future<void> submitPasswordReset({
    required String newPassword,
    required String code,
  }) async {
    final email = state.email;
    if (!state.isSignedIn || email == null) return;
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final keys = await _crypto.deriveAccountKeys(
      email: email,
      password: newPassword,
    );

    // 1. Local first, keeping the old wrap to put back.
    final previous = await _vaultCubit.storedSeedWrap();
    _wrapChangeInFlight = true;
    try {
      final rewrapped = await _vaultCubit.rewrapSeed(
        newPassword: keys.vaultPassword,
        wrapEmail: email,
      );
      if (!rewrapped.success) {
        emit(state.copyWith(isProcessing: false, error: rewrapped.error));
        return;
      }

      // 2. GoTrue checks the code here, and refuses the password without it.
      final updated = await _repo.updatePassword(
        password: keys.authPassword,
        nonce: code,
      );
      if (!updated.success &&
          !await _landedAnyway(updated, email, keys.authPassword)) {
        // 3. Back to the wrap the account's password still opens.
        await _vaultCubit.restoreSeedWrap(previous);
        emit(state.copyWith(isProcessing: false, error: updated.error));
        return;
      }
    } finally {
      _wrapChangeInFlight = false;
    }
    _accountVaultPassword = keys.vaultPassword;

    // The code has been proved, so a new recovery key may be minted. Showing
    // it is the router's: a pending key outranks every other screen.
    final reissued = await _vaultCubit.reissueRecoveryKey();
    if (!reissued.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] new recovery key failed: ${reissued.error}',
      );
    }

    emit(state.copyWith(passwordChange: PasswordChangeStage.idle));

    // 4. The stored backup still holds the old wraps. Should this fail, the
    // next pull finds this device's wraps newer and pushes them.
    final done = reissued.success
        ? 'Password changed.'
        : 'Password changed. Replace your recovery key from this page.';
    if (!await _uploadBackup(successMessage: done) &&
        !state.cloudBackupConflict) {
      emit(
        state.copyWith(
          clearMessage: true,
          successMessage:
              '$done Your cloud backup will catch up when Rift can reach it.',
        ),
      );
    }
  }
}
