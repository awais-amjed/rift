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
      // "You never confirmed your address" is not a failed sign-in so much as
      // an unfinished sign-up, and it is where most people meet this screen:
      // the confirmation mail was lost, or the link expired, and by then the
      // one-time notice they saw at sign-up is long gone. So the attempt is set
      // aside and they land back on that notice, which is the only place that
      // can offer another email.
      if (response.errorCode == ErrorCode.emailNotConfirmed) {
        emit(
          state.copyWith(
            isProcessing: false,
            needsEmailConfirmation: true,
            email: email,
          ),
        );
        return;
      }
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

  /// Asks for another confirmation email.
  ///
  /// Only reachable from the notice, so [SupabaseBackupState.email] is the
  /// address that was signed up with. There is no field to retype it into on
  /// purpose — one would turn this screen into a way of sending mail to any
  /// address anybody cares to enter.
  ///
  /// A refusal still starts the cooldown. The server enforces its own gap, and
  /// a button that stays live after being told "not for another 47 seconds"
  /// invites exactly the tapping that spends the project's hourly allowance.
  Future<void> resendConfirmation() async {
    final email = state.email;
    if (email == null || state.isProcessing) return;
    final until = state.resendAvailableAt;
    if (until != null && until.isAfter(DateTime.now())) return;

    emit(state.copyWith(isProcessing: true, clearMessage: true));
    final response = await _repo.resendConfirmation(email: email);
    final resendAvailableAt = DateTime.now().add(
      SupabaseBackupCubit.resendCooldown,
    );

    if (!response.success) {
      HelperMethods.printDebug(
        '[SupabaseBackup] resend failed: ${response.error}',
      );
      emit(
        state.copyWith(
          isProcessing: false,
          resendAvailableAt: resendAvailableAt,
          // The server's own wording for a rate limit, because it names the
          // wait. Anything else is replaced: GoTrue's other messages are
          // written for a developer reading a log.
          error: response.errorCode == ErrorCode.emailSendRateLimited
              ? response.error
              : 'Could not send the email just now. Try again in a minute.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isProcessing: false,
        resendAvailableAt: resendAvailableAt,
        // Deliberately not "we sent it". The server does not say whether the
        // address is real, already confirmed, or unknown to it, and it should
        // not — an answer either way would make this a way of asking which
        // emails hold accounts.
        successMessage:
            'If $email is waiting to be confirmed, another link is on its '
            'way. Check spam too.',
      ),
    );
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
