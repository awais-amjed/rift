part of 'vault_cubit.dart';

/// Immutable state for [VaultCubit].
class VaultState {
  final AuthStatus status;
  final bool isProcessing;
  final String? error;

  /// The decrypted master seed (base64), kept in memory after unlock.
  /// Never persisted outside of secure storage.
  final String? masterSeed;

  /// A generated recovery key the person has not confirmed seeing yet.
  ///
  /// Held in state, not just in storage, because the router treats it as a
  /// gate: while it is set, the app is not finished starting up. Null in every
  /// other circumstance, including for vaults created before recovery keys.
  final String? pendingRecoveryKey;

  const VaultState({
    this.status = AuthStatus.unknown,
    this.isProcessing = false,
    this.error,
    this.masterSeed,
    this.pendingRecoveryKey,
  });

  VaultState copyWith({
    AuthStatus? status,
    bool? isProcessing,
    String? error,
    bool clearError = false,
    String? masterSeed,
    String? pendingRecoveryKey,
    bool clearPendingRecoveryKey = false,
  }) {
    return VaultState(
      status: status ?? this.status,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
      masterSeed: masterSeed ?? this.masterSeed,
      pendingRecoveryKey: clearPendingRecoveryKey
          ? null
          : (pendingRecoveryKey ?? this.pendingRecoveryKey),
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
          masterSeed == other.masterSeed &&
          pendingRecoveryKey == other.pendingRecoveryKey;

  @override
  int get hashCode =>
      Object.hash(status, isProcessing, error, masterSeed, pendingRecoveryKey);

  @override
  String toString() =>
      'VaultState(status: $status, isProcessing: $isProcessing, error: $error)';
}
