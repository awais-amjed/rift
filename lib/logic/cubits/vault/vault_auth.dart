part of 'vault_cubit.dart';

mixin _VaultAuthMixin on Cubit<VaultState> {
  SecureStorageRepository get _storage;

  /// Implemented by [_VaultRecoveryMixin].
  Future<String?> loadPendingRecoveryKey();
  SessionRepository get _session;

  // ──────────────────────────────────────────────────────────
  // Startup check
  // ──────────────────────────────────────────────────────────

  /// Checks for an existing vault in secure storage and sets initial auth status.
  Future<void> checkVaultStatus() async {
    try {
      final masterSeed = await _storage.getMasterSeed();
      if (masterSeed != null) {
        // A key generated but never acknowledged outlives the process that
        // generated it — the app was closed on the screen showing it, and it
        // has to come back or the blob is unopenable by anyone.
        emit(
          VaultState(
            status: AuthStatus.unlocked,
            masterSeed: masterSeed,
            pendingRecoveryKey: await loadPendingRecoveryKey(),
          ),
        );
      } else {
        emit(const VaultState(status: AuthStatus.fresh));
      }
    } catch (e) {
      HelperMethods.printDebug('[Vault] checkVaultStatus error: $e');
      emit(VaultState(status: AuthStatus.fresh, error: e.toString()));
    }
  }

  /// The state once [checkVaultStatus] has answered.
  ///
  /// Reading secure storage takes a moment, and the app does not wait for it
  /// before making server calls. After a night off every stored token has
  /// expired, so those first calls go straight to a re-login — which needs the
  /// seed that has not been read yet. Anything that needs the seed waits here.
  Future<VaultState> settled() async {
    if (state.status != AuthStatus.unknown) return state;
    return stream
        .firstWhere((s) => s.status != AuthStatus.unknown)
        .timeout(const Duration(seconds: 10), onTimeout: () => state);
  }

  // ──────────────────────────────────────────────────────────
  // Sign-in-with-Web3 (SIWS) login
  // ──────────────────────────────────────────────────────────

  /// Sign a SIWS message with this server's Ed25519 key and exchange it for a
  /// GoTrue session via the `login` proxy. Returns the access token (JWT).
  /// [serverId] scopes the identity so servers sharing a host (project) sign
  /// in as distinct users. The signing is [SessionRepository]'s, which every
  /// later re-login goes through too.
  Future<({String? accessToken, String? error})> siwsLogin(
    String supabaseUrl, {
    required String serverId,
  }) => _session.signIn(supabaseUrl, serverId: serverId);
}
