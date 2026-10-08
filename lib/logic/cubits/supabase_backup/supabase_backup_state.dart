part of 'supabase_backup_cubit.dart';

/// Where a password change has got to.
///
/// A change is a conversation, not a single call: prove the old password, then
/// (on an account) prove the address, then set the new one. The UI needs to
/// know which question it is asking.
enum PasswordChangeStage {
  /// Nothing in progress — the form asks for the current password.
  idle,

  /// Current password proved and a code emailed. Waiting for the code and the
  /// new password.
  enterCode,

  /// Current password proved and there is no address to confirm — privacy
  /// mode. Waiting for the new password alone.
  enterNew,
}

/// Where account recovery has got to.
enum AccountRecoveryStage {
  /// Not recovering — the sign-in form is showing.
  idle,

  /// In the flow, but no code asked for yet: confirming which address.
  enterEmail,

  /// A code was requested. Waiting for it, the recovery key, and a new
  /// password.
  enterCode,
}

/// Immutable state for [SupabaseBackupCubit].
class SupabaseBackupState {
  final bool isProcessing;
  final bool isSignedIn;
  final bool needsEmailConfirmation;

  /// A cloud backup exists but the derived account password can't decrypt it
  /// (it was exported with a manually chosen vault password). The UI should
  /// prompt and call [SupabaseBackupCubit.submitVaultPassword].
  final bool needsVaultPassword;

  /// Both a local vault and a cloud backup exist after sign-in. The UI should
  /// ask the user to resolve via [SupabaseBackupCubit.keepLocalVault] or
  /// [SupabaseBackupCubit.restoreCloudBackup].
  final bool cloudBackupConflict;

  final String? email;

  /// When another confirmation email may be asked for, or null when one may be
  /// asked for now.
  ///
  /// A time rather than a countdown so the UI owns the ticking: a cubit that
  /// emitted once a second would rebuild the whole backup screen for the sake
  /// of two digits.
  final DateTime? resendAvailableAt;

  /// Where a password change has got to. See [PasswordChangeStage].
  final PasswordChangeStage passwordChange;

  /// Where account recovery has got to. See [AccountRecoveryStage].
  final AccountRecoveryStage accountRecovery;

  final String? error;
  final String? successMessage;

  /// The last thing to tell the person, shown once by `NoticeListeners`.
  final Notice? notice;

  const SupabaseBackupState({
    this.isProcessing = false,
    this.isSignedIn = false,
    this.needsEmailConfirmation = false,
    this.needsVaultPassword = false,
    this.cloudBackupConflict = false,
    this.email,
    this.resendAvailableAt,
    this.passwordChange = PasswordChangeStage.idle,
    this.accountRecovery = AccountRecoveryStage.idle,
    this.error,
    this.successMessage,
    this.notice,
  });

  SupabaseBackupState copyWith({
    bool? isProcessing,
    bool? isSignedIn,
    bool? needsEmailConfirmation,
    bool? needsVaultPassword,
    bool? cloudBackupConflict,
    String? email,
    DateTime? resendAvailableAt,
    PasswordChangeStage? passwordChange,
    AccountRecoveryStage? accountRecovery,
    String? error,
    String? successMessage,
    bool clearMessage = false,
    Notice? notice,
  }) {
    return SupabaseBackupState(
      isProcessing: isProcessing ?? this.isProcessing,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      needsEmailConfirmation:
          needsEmailConfirmation ?? this.needsEmailConfirmation,
      needsVaultPassword: needsVaultPassword ?? this.needsVaultPassword,
      cloudBackupConflict: cloudBackupConflict ?? this.cloudBackupConflict,
      email: email ?? this.email,
      resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
      passwordChange: passwordChange ?? this.passwordChange,
      accountRecovery: accountRecovery ?? this.accountRecovery,
      error: clearMessage ? null : (error ?? this.error),
      successMessage: clearMessage
          ? null
          : (successMessage ?? this.successMessage),
      notice: notice ?? this.notice,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupabaseBackupState &&
          runtimeType == other.runtimeType &&
          isProcessing == other.isProcessing &&
          isSignedIn == other.isSignedIn &&
          needsEmailConfirmation == other.needsEmailConfirmation &&
          needsVaultPassword == other.needsVaultPassword &&
          cloudBackupConflict == other.cloudBackupConflict &&
          email == other.email &&
          resendAvailableAt == other.resendAvailableAt &&
          passwordChange == other.passwordChange &&
          accountRecovery == other.accountRecovery &&
          error == other.error &&
          successMessage == other.successMessage &&
          notice == other.notice;

  @override
  int get hashCode => Object.hash(
    isProcessing,
    isSignedIn,
    needsEmailConfirmation,
    needsVaultPassword,
    cloudBackupConflict,
    email,
    resendAvailableAt,
    passwordChange,
    accountRecovery,
    error,
    successMessage,
    notice,
  );
}
