import 'package:equatable/equatable.dart';

import 'encrypted_seed.dart';
import 'encrypted_vault.dart';

/// Everything secure storage holds about one vault, written as one.
///
/// Creating a vault and restoring a backup each replace several stored values
/// at once, and the store writes one value at a time. Killed between two
/// writes, a device kept one vault's seed beside another's wraps, and the next
/// upload sent that mixture to the cloud. So the whole record goes into one
/// value first (`SecureStorageRepository.replaceVault`), which a start that
/// finds it applies again before reading anything else.
class StoredVault extends Equatable {
  final String masterSeed;
  final List<({String url, String version})> joinedServers;
  final EncryptedSeed seed;
  final EncryptedVault vault;

  /// Null removes the stored recovery wrap: a backup without one carries no
  /// key this device could open it with, and the old vault's wrap is not this
  /// one's.
  final EncryptedSeed? recovery;

  /// A key shown and not yet acknowledged. Null clears one left behind.
  final String? pendingRecoveryKey;

  /// When the seed and recovery wraps last changed, in milliseconds since the
  /// epoch (`SecureStorageRepository.getWrapsAt`).
  final int wrapsAt;

  /// The account whose password wraps the seed, or null when the typed
  /// password does (`SecureStorageRepository.getSeedWrapEmail`).
  final String? seedWrapEmail;

  const StoredVault({
    required this.masterSeed,
    required this.joinedServers,
    required this.seed,
    required this.vault,
    required this.recovery,
    required this.pendingRecoveryKey,
    required this.wrapsAt,
    required this.seedWrapEmail,
  });

  Map<String, dynamic> toJson() => {
    'master_seed': masterSeed,
    'joined_servers': joinedServers
        .map((s) => {'url': s.url, 'version': s.version})
        .toList(),
    'seed': seed.toJson(),
    'vault': vault.toJson(),
    if (recovery != null) 'recovery': recovery!.toJson(),
    if (pendingRecoveryKey != null) 'pending_recovery_key': pendingRecoveryKey,
    'wraps_at': wrapsAt,
    if (seedWrapEmail != null) 'seed_wrap_email': seedWrapEmail,
  };

  factory StoredVault.fromJson(Map<String, dynamic> json) => StoredVault(
    masterSeed: json['master_seed'] as String,
    joinedServers: (json['joined_servers'] as List<dynamic>).map((e) {
      final m = e as Map<String, dynamic>;
      return (url: m['url'] as String, version: m['version'] as String);
    }).toList(),
    seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
    vault: EncryptedVault.fromJson(json['vault'] as Map<String, dynamic>),
    recovery: json['recovery'] == null
        ? null
        : EncryptedSeed.fromJson(json['recovery'] as Map<String, dynamic>),
    pendingRecoveryKey: json['pending_recovery_key'] as String?,
    wrapsAt: (json['wraps_at'] as num?)?.toInt() ?? 0,
    seedWrapEmail: json['seed_wrap_email'] as String?,
  );

  @override
  List<Object?> get props => [
    masterSeed,
    joinedServers,
    seed,
    vault,
    recovery,
    pendingRecoveryKey,
    wrapsAt,
    seedWrapEmail,
  ];
}
