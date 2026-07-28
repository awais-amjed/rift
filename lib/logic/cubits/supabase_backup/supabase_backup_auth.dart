part of 'supabase_backup_cubit.dart';

/// Account creation, sign-in and sign-out against the central server. The
/// typed password never leaves the device: it is split into an auth verifier
/// and a vault password (ARCHITECTURE.md §3) before anything is sent.
mixin _SupabaseBackupAuthMixin on Cubit<SupabaseBackupState> {
  SupabaseBackupRepository get _repo;
  CryptoRepository get _crypto;
  Timer? get _autoBackupTimer;
  set _accountVaultPassword(String? value);
  set _pendingCloudBackup(String? value);
  set _intentionalSignOut(bool value);

  /// Implemented by the cubit — reconciles vault and cloud after a session
  /// starts.
  Future<void> _postAuthSync();

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
}
