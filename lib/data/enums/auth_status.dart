/// Possible authentication statuses for the vault.
enum AuthStatus {
  /// Initial state — checking secure storage.
  unknown,

  /// No vault exists yet. Show onboarding.
  fresh,

  /// Vault created, master seed available in memory. App is ready.
  unlocked,

  /// Secure storage could not be read — a locked keyring, a keystore error.
  /// Not [fresh]: a vault may well be there, and onboarding would offer to
  /// make another over it. The app says so and offers to try again.
  unreadable,
}
