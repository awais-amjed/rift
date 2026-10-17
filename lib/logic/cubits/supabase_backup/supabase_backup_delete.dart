part of 'supabase_backup_cubit.dart';

/// Deleting the central account (`delete_account`).
///
/// What goes is everything the account held on central. What stays is this
/// device's vault and every server on it, since none of those were ever the
/// account's (ARCHITECTURE.md §3). Two things keep that true afterwards: the
/// session is let go the way a sign-out lets it go, and the seed blob, wrapped
/// under the account's derived password since this device signed in, is
/// wrapped again under the typed one, which is what opens a vault with no
/// account. Without that, the next password change or export here would
/// refuse the password the person knows.
mixin _SupabaseBackupDeleteMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  CryptoRepository get _crypto;
  VaultCubit get _vaultCubit;
  Timer? get _autoBackupTimer;
  set _accountVaultPassword(String? value);
  set _pendingCloudBackup(String? value);
  set _intentionalSignOut(bool value);

  /// Deletes the signed-in account, proving [password] again first. The
  /// refusal comes back to the dialog that asked, not into [state].
  ///
  /// The password is checked by central, not against the local blob as a
  /// password change does: the blob may have been wrapped under another
  /// password before this device signed in, and that must not stand between
  /// somebody and deleting their account.
  Future<({bool success, String? error})> deleteAccount({
    required String password,
  }) async {
    final email = state.email;
    if (!state.isSignedIn || email == null) {
      return (success: false, error: 'You are not signed in.');
    }
    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final keys = await _crypto.deriveAccountKeys(
      email: email,
      password: password,
    );

    _intentionalSignOut = true;
    final response = await _repo.deleteAccount(
      email: email,
      password: keys.authPassword,
    );
    if (!response.success) {
      _intentionalSignOut = false;
      emit(state.copyWith(isProcessing: false));
      final wrongPassword = response.errorCode == 'invalid_credentials';
      return (
        success: false,
        error: wrongPassword ? 'That is not your password.' : response.error,
      );
    }

    if (await _vaultCubit.verifyVaultPassword(keys.vaultPassword)) {
      final rewrapped = await _vaultCubit.changeVaultPassword(
        oldPassword: keys.vaultPassword,
        newPassword: password,
      );
      if (!rewrapped.success) {
        HelperMethods.printDebug(
          '[SupabaseBackup] re-wrapping the seed after deleting the account '
          'failed: ${rewrapped.error}',
        );
      }
    }
    _accountVaultPassword = null;
    _pendingCloudBackup = null;
    _autoBackupTimer?.cancel();
    emit(
      SupabaseBackupState(
        notice: Notice.success(
          'Account deleted',
          'Your Rift account and everything on it is gone. Your servers stay '
              'on this device.',
        ),
      ),
    );
    return (success: true, error: null);
  }
}
