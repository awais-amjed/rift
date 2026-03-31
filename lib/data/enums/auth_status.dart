/// Possible authentication statuses for the vault.
enum AuthStatus {
  /// Initial state — checking secure storage.
  unknown,

  /// No vault exists yet. Show onboarding.
  fresh,

  /// Vault created, master seed available in memory. App is ready.
  unlocked,
}

