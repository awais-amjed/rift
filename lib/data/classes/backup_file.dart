import 'dart:convert';

import 'encrypted_seed.dart';
import 'encrypted_vault.dart';

/// Portable backup file combining the encrypted master seed and vault metadata.
///
/// File layout (JSON):
/// ```
///   seed_*   → AES-GCM( Argon2id(password, salt),  masterSeed )
///   vault_*  → AES-GCM( HMAC(masterSeed, "vault:v1"), joined_servers )
/// ```
///
/// Restore flow on a new device:
///   1. Enter password → Argon2id(password, seed_salt) → decrypt seed → masterSeed
///   2. HMAC(masterSeed, "vault:v1") → decrypt vault → joined_servers
///   3. Store both in secure storage and derive all server identities.
class BackupFile {
  static const int currentVersion = 1;

  final int version;
  final EncryptedSeed seed;
  final EncryptedVault vault;

  const BackupFile({
    required this.version,
    required this.seed,
    required this.vault,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'seed': seed.toJson(),
        'vault': vault.toJson(),
      };

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
        version: json['version'] as int,
        seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
        vault: EncryptedVault.fromJson(json['vault'] as Map<String, dynamic>),
      );

  String toJsonString() => jsonEncode(toJson());

  factory BackupFile.fromJsonString(String s) =>
      BackupFile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

