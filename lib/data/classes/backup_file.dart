import 'dart:convert';

import 'encrypted_seed.dart';
import 'encrypted_vault.dart';

/// Portable backup file combining the encrypted master seed and vault metadata.
///
/// File layout (JSON):
/// ```
///   seed_*   → AES-GCM( Argon2id(password, salt),  masterSeed )
///   vault_*  → AES-GCM( HMAC(masterSeed, "vault:v1"), joined_servers )
///   servers  → plain list of server metadata (id, name, urls, keyVersion)
///              used to restore the server list on a fresh device
/// ```
///
/// Restore flow on a new device:
///   1. Enter password → Argon2id(password, seed_salt) → decrypt seed → masterSeed
///   2. HMAC(masterSeed, "vault:v1") → decrypt vault → joined_servers
///   3. Store both in secure storage and derive all server identities.
///   4. Reconstruct Server objects from [servers] and populate ServerCubit.
class BackupFile {
  static const int currentVersion = 1;

  final int version;
  final EncryptedSeed seed;
  final EncryptedVault vault;

  /// Full server metadata for each joined server.
  /// Each entry contains: id, name, iconUrl, supabaseUrl, supabaseKey,
  /// livekitUrl, keyVersion. Token is intentionally excluded.
  final List<Map<String, dynamic>> servers;

  const BackupFile({
    required this.version,
    required this.seed,
    required this.vault,
    this.servers = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'seed': seed.toJson(),
        'vault': vault.toJson(),
        'servers': servers,
      };

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
        version: json['version'] as int,
        seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
        vault: EncryptedVault.fromJson(json['vault'] as Map<String, dynamic>),
        servers: (json['servers'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
      );

  String toJsonString() => jsonEncode(toJson());

  factory BackupFile.fromJsonString(String s) =>
      BackupFile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

