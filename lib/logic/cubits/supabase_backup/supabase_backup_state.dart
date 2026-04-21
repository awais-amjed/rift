part of 'supabase_backup_cubit.dart';

/// Immutable state for [SupabaseBackupCubit].
class SupabaseBackupState {
  final bool isProcessing;
  final bool isSignedIn;
  final bool needsEmailConfirmation;
  final String? email;
  final String? error;
  final String? successMessage;

  const SupabaseBackupState({
    this.isProcessing = false,
    this.isSignedIn = false,
    this.needsEmailConfirmation = false,
    this.email,
    this.error,
    this.successMessage,
  });

  SupabaseBackupState copyWith({
    bool? isProcessing,
    bool? isSignedIn,
    bool? needsEmailConfirmation,
    String? email,
    String? error,
    String? successMessage,
    bool clearMessage = false,
  }) {
    return SupabaseBackupState(
      isProcessing: isProcessing ?? this.isProcessing,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      needsEmailConfirmation:
          needsEmailConfirmation ?? this.needsEmailConfirmation,
      email: email ?? this.email,
      error: clearMessage ? null : (error ?? this.error),
      successMessage:
          clearMessage ? null : (successMessage ?? this.successMessage),
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
          email == other.email &&
          error == other.error &&
          successMessage == other.successMessage;

  @override
  int get hashCode => Object.hash(
        isProcessing,
        isSignedIn,
        needsEmailConfirmation,
        email,
        error,
        successMessage,
      );
}
