part of 'supabase_backup_cubit.dart';

/// Getting back in when the password is the thing that was lost.
///
/// Two halves that have to happen together, because each is useless alone:
///
/// - the **account** is recovered by email, the ordinary way — a code proves
///   the address, and a new verifier is set from it;
/// - the **vault** is recovered by the recovery key, and only by it. The
///   backup in the cloud is wrapped under the forgotten password; no code, no
///   support request and no server-side reset opens it. That is the property
///   the encryption is for, and it is why the key had to be issued up front.
///
/// The whole exchange stays inside the app rather than following the link in
/// the email into a browser. It has to: the value GoTrue stores is
/// `KDF(typed, "auth")`, and a web page setting a password directly would
/// leave an account the client could never sign in to again.
mixin _SupabaseBackupAccountRecoveryMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  CryptoRepository get _crypto;
  VaultCubit get _vaultCubit;

  set _accountVaultPassword(String? value);

  /// Open the recovery flow, carrying over whatever address was typed.
  ///
  /// Deliberately does not send anything yet: the address on the sign-in form
  /// is often blank or half-typed, and mailing a code to it before it has been
  /// confirmed would spend a rate limit on a guess.
  void startAccountRecovery({String? email}) => emit(
    state.copyWith(
      accountRecovery: AccountRecoveryStage.enterEmail,
      email: (email != null && email.isNotEmpty) ? email : null,
      clearMessage: true,
    ),
  );

  /// Ask for a recovery code.
  ///
  /// Succeeds the same way whether or not the address has an account — see
  /// [SupabaseBackupRepository.sendPasswordRecovery] — so the message is
  /// deliberately conditional.
  Future<void> beginAccountRecovery({required String email}) async {
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) {
      emit(state.copyWith(error: 'Enter a valid email address'));
      return;
    }

    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final sent = await _repo.sendPasswordRecovery(email: address);
    if (!sent.success) {
      emit(state.copyWith(isProcessing: false, error: sent.error));
      return;
    }

    emit(
      state.copyWith(
        isProcessing: false,
        email: address,
        accountRecovery: AccountRecoveryStage.enterCode,
        successMessage:
            'If $address has an account, a code is on its way. Check spam too.',
      ),
    );
  }

  /// Finish: prove the address, set a new password, and open the vault with
  /// the recovery key.
  ///
  /// Ordered so nothing irreversible happens before the recoverable parts are
  /// known to work. In particular the recovery key is checked against the real
  /// backup *after* the password is set, because there is no way to check it
  /// before downloading the backup, and the backup needs a session. A wrong
  /// key at that point leaves the account usable with its new password and the
  /// vault still waiting — which is recoverable by trying again, unlike any
  /// other ordering.
  Future<void> completeAccountRecovery({
    required String code,
    required String recoveryKey,
    required String newPassword,
  }) async {
    final email = state.email;
    if (email == null) {
      emit(state.copyWith(error: 'Start again — no address to recover.'));
      return;
    }

    // Cheap and local: reject a malformed key before spending a code on it.
    if (_crypto.normalizeRecoveryKey(recoveryKey) == null) {
      emit(state.copyWith(error: 'That does not look like a recovery key'));
      return;
    }

    emit(state.copyWith(isProcessing: true, clearMessage: true));

    final verified = await _repo.verifyRecoveryCode(
      email: email,
      token: code.trim(),
    );
    if (!verified.success) {
      emit(state.copyWith(isProcessing: false, error: verified.error));
      return;
    }

    // The session from the code is itself the proof, so no nonce here.
    final keys = await _crypto.deriveAccountKeys(
      email: email,
      password: newPassword,
    );
    final updated = await _repo.updatePassword(password: keys.authPassword);
    if (!updated.success) {
      emit(state.copyWith(isProcessing: false, error: updated.error));
      return;
    }

    final downloaded = await _repo.downloadBackup();
    if (!downloaded.success) {
      emit(state.copyWith(isProcessing: false, error: downloaded.error));
      return;
    }

    final backupJson = downloaded.data as String?;
    if (backupJson == null) {
      // Nothing stored: the account is recovered and there is no vault to
      // open. Signing in normally will make one.
      _accountVaultPassword = keys.vaultPassword;
      emit(
        state.copyWith(
          isProcessing: false,
          isSignedIn: true,
          accountRecovery: AccountRecoveryStage.idle,
          successMessage:
              'Password reset. There was no backup on this account.',
        ),
      );
      return;
    }

    final imported = await _vaultCubit.importBackup(
      jsonContent: backupJson,
      recoveryKey: recoveryKey,
    );
    if (!imported.success) {
      emit(
        state.copyWith(
          isProcessing: false,
          isSignedIn: true,
          error: imported.error ?? 'That recovery key did not open the backup.',
        ),
      );
      return;
    }

    // The imported seed blob is still wrapped under the password nobody
    // remembers. Re-wrap it under the new one, or the next sign-in on this
    // device would have to come through recovery all over again.
    final rewrapped = await _vaultCubit.rewrapSeed(
      newPassword: keys.vaultPassword,
    );
    if (!rewrapped.success) {
      emit(state.copyWith(isProcessing: false, error: rewrapped.error));
      return;
    }

    _accountVaultPassword = keys.vaultPassword;
    emit(
      state.copyWith(
        isSignedIn: true,
        email: email,
        accountRecovery: AccountRecoveryStage.idle,
      ),
    );
    await _uploadBackup(successMessage: 'Account recovered.');
  }

  /// Leave the recovery flow.
  void cancelAccountRecovery() => emit(
    state.copyWith(
      accountRecovery: AccountRecoveryStage.idle,
      clearMessage: true,
    ),
  );

  Future<void> _uploadBackup({required String successMessage});
}
