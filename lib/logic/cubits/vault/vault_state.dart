part of 'vault_cubit.dart';

/// Immutable state for [VaultCubit].
class VaultState {
  final AuthStatus status;
  final bool isProcessing;
  final String? error;

  /// The decrypted master seed (base64), kept in memory after unlock.
  /// Never persisted outside of secure storage.
  final String? masterSeed;

  const VaultState({
    this.status = AuthStatus.unknown,
    this.isProcessing = false,
    this.error,
    this.masterSeed,
  });

  VaultState copyWith({
    AuthStatus? status,
    bool? isProcessing,
    String? error,
    bool clearError = false,
    String? masterSeed,
  }) {
    return VaultState(
      status: status ?? this.status,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
      masterSeed: masterSeed ?? this.masterSeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          isProcessing == other.isProcessing &&
          error == other.error &&
          masterSeed == other.masterSeed;

  @override
  int get hashCode => Object.hash(status, isProcessing, error, masterSeed);

  @override
  String toString() =>
      'VaultState(status: $status, isProcessing: $isProcessing, error: $error)';
}
