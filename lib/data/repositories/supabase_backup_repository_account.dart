part of 'supabase_backup_repository.dart';

/// The account on central: signing up, in and out, confirming the address,
/// changing and recovering the password, and deleting it.
///
/// Its own part because the backup is one object in a bucket, and the account
/// is everything GoTrue does.
mixin _CentralAccountMixin {
  SupabaseClient get _client;

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Auth state changes (sign-in/out, token refresh). Emits `signedOut` when
  /// the session is lost — e.g. the account was deleted server-side and the
  /// token can no longer be refreshed.
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  /// Signs up a new user on the central server.
  ///
  /// On success [APIResponse.data] is a map:
  ///   `{ 'user': User?, 'needsConfirmation': bool }`
  /// [handle] rides in the auth user's metadata rather than being claimed
  /// here: the directory row needs two public keys that only a signed-in
  /// session with the seed can derive, and with confirmation on there is no
  /// session yet. `CentralDmCubit` claims it the first time there is one.
  Future<APIResponse> signUp({
    required String email,
    required String password,
    required String handle,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: SupabaseConfig.emailConfirmationRedirect,
        data: {'handle': handle},
      );

      // Session is null → email confirmation required.
      if (response.session == null) {
        return APIResponse.success({'user': null, 'needsConfirmation': true});
      }

      final user = response.user;
      if (user == null) {
        return APIResponse.error('Sign-up succeeded but no user was returned.');
      }
      return APIResponse.success({'user': user, 'needsConfirmation': false});
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Whether nobody has [handle] yet. Answerable
  /// before there is an account, which is the point: the refusal belongs on
  /// the sign-up form, not on the DM tab a day later.
  Future<APIResponse> isHandleAvailable(String handle) async {
    try {
      final free = await _client.rpc(
        'is_handle_available',
        params: {'p_handle': handle},
      );
      return APIResponse.success(free == true);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Signs in an existing user.
  ///
  /// On success [APIResponse.data] is the [User].
  Future<APIResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return APIResponse.error('Sign-in succeeded but no user was returned.');
      }
      return APIResponse.success(user);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Sends the confirmation email again for an address that has signed up and
  /// never confirmed.
  ///
  /// Supabase does not tell us whether the address exists, is already
  /// confirmed, or was never seen — and should not. An unauthenticated caller
  /// learning which emails hold accounts is exactly the enumeration a sign-up
  /// form is careful to avoid, so a success here means "the request was
  /// accepted", not "an email is on its way to a real account".
  ///
  /// Rate limited by the server on two axes: a minimum gap between two emails
  /// to one address, and a project-wide hourly cap. A refusal comes back as
  /// [ErrorCode.emailSendRateLimited] with the server's own wording, which
  /// usually names the number of seconds left.
  Future<APIResponse> resendConfirmation({required String email}) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: SupabaseConfig.emailConfirmationRedirect,
      );
      return APIResponse.success(null);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Ask GoTrue to email a one-time code for a password change.
  ///
  /// Requires a live session — this is the "prove it is still you" step, not a
  /// way in from outside. GoTrue calls the code a *nonce* and will not accept
  /// [updatePassword] without one.
  Future<APIResponse> sendReauthenticationCode() async {
    try {
      await _client.auth.reauthenticate();
      return APIResponse.success(null);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Set a new login password, proving possession of the emailed [nonce].
  ///
  /// **[password] is the derived auth verifier, never what the user typed.**
  /// The account's stored password is `KDF(typed, "auth")` (see
  /// [SupabaseConfig] and ARCHITECTURE.md §3); handing GoTrue the raw string
  /// here would leave an account whose password the client can never
  /// reproduce, and no way back into it.
  /// [nonce] is omitted when the session was *just* established by a recovery
  /// code — verifying that code is itself the proof, and GoTrue asks for a
  /// nonce only when the session predates the request.
  Future<APIResponse> updatePassword({
    required String password,
    String? nonce,
  }) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(password: password, nonce: nonce),
      );
      return APIResponse.success(null);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Start account recovery: GoTrue emails a code to [email].
  ///
  /// Unauthenticated by nature — this is the way in when the password is the
  /// thing that was lost. It says nothing about whether the address has an
  /// account, and must not: an answer either way turns this into a way of
  /// asking which emails are registered.
  Future<APIResponse> sendPasswordRecovery({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return APIResponse.success(null);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Exchange an emailed recovery code for a session.
  ///
  /// Needs `{{ .Token }}` in the project's recovery template — the link in
  /// that mail is a PKCE URL meant for a browser, and this flow deliberately
  /// stays in the app so the password derivation never leaves the device.
  Future<APIResponse> verifyRecoveryCode({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.recovery,
      );
      final user = response.user;
      if (user == null) {
        return APIResponse.error('That code did not open a session.');
      }
      return APIResponse.success(user);
    } on AuthException catch (e) {
      return _authFailure(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Keeps GoTrue's machine-readable code alongside its message.
  ///
  /// Without this every auth failure reached the cubit as a sentence and
  /// nothing else, so "your address is not confirmed yet" was indistinguishable
  /// from "that password is wrong" — one of which has an obvious next step and
  /// the other of which does not.
  ///
  /// Central not answering is not one of GoTrue's codes, and its message is
  /// the socket error — so that is worded first ([CentralFailure]).
  APIResponse _authFailure(AuthException e) => CentralFailure.isUnreachable(e)
      ? CentralFailure.response(e)
      : APIResponse(success: false, error: e.message, errorCode: e.code);

  /// Signs out the current user.
  Future<APIResponse> signOut() async {
    try {
      await _client.auth.signOut();
      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Deletes the signed-in account and everything central holds for it
  /// (`delete_account`): the profile, DMs, contacts, listings and the backup.
  ///
  /// Signs in again with [password] (the auth verifier) first, because the
  /// function refuses a session that did not start with a password minutes
  /// ago — an unlocked phone is not enough to destroy an account. Afterwards
  /// only this device's session is dropped: the server has no user left to
  /// sign out of, and the other devices find out when theirs cannot refresh.
  Future<APIResponse> deleteAccount({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      await _client.functions.invoke('delete_account');
    } on AuthException catch (e) {
      return _authFailure(e);
    } on FunctionException catch (e) {
      if (CentralFailure.isUnreachable(e)) return CentralFailure.response(e);
      final detail = e.details;
      final code = detail is Map && detail['error'] != null
          ? '${detail['error']}'
          : 'unexpected_error';
      return APIResponse(
        success: false,
        error: _deleteFailure(code),
        errorCode: code,
      );
    } catch (e) {
      return CentralFailure.response(e);
    }
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The account is gone either way; a session left on disk cannot
      // refresh, and the next start drops it.
    }
    return APIResponse.success(null);
  }

  static String _deleteFailure(String code) => switch (code) {
    'reauthentication_needed' => 'Sign in again, then try once more.',
    'moderator_account' => 'A moderator account cannot be deleted here.',
    'not_authenticated' => 'You are signed out. Sign in, then try again.',
    _ => "Couldn't delete the account. Try again in a moment.",
  };
}
