import 'dart:convert';

import 'encrypted_seed.dart';
import 'encrypted_vault.dart';

/// Portable backup file combining the encrypted master seed and vault metadata.
///
/// File layout (JSON):
/// ```
///   seed             → AES-GCM( Argon2id(password, salt),  masterSeed )
///   vault            → AES-GCM( HMAC(masterSeed, "vault:v1"), joined_servers )
///   encryptedServers → AES-GCM( HMAC(masterSeed, "vault:v1"), servers JSON )
/// ```
///
/// All three blobs are encrypted. The `encryptedServers` blob uses the same
/// vault key but a separate IV, keeping server metadata opaque to the storage
/// provider.
///
/// Restore flow on a new device:
///   1. Enter password → Argon2id(password, seed_salt) → decrypt seed → masterSeed
///   2. HMAC(masterSeed, "vault:v1") → decrypt vault → joined_servers
///   3. Same vault key + encryptedServers.iv → decrypt servers → server list
///   4. Store everything in secure storage and derive all server identities.
///   5. Reconstruct Server objects from decrypted servers and populate ServerCubit.
class BackupFile {
  static const int currentVersion = 2;

  final int version;
  final EncryptedSeed seed;
  final EncryptedVault vault;

  /// AES-GCM encrypted JSON array of full server metadata.
  /// Key = HMAC(masterSeed, "vault:v1") — same key as [vault], separate IV.
  /// Each entry: id, name, iconUrl, supabaseUrl, supabaseKey, livekitUrl,
  /// keyVersion. Token is intentionally excluded.
  final EncryptedVault? encryptedServers;

  const BackupFile({
    required this.version,
    required this.seed,
    required this.vault,
    this.encryptedServers,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'seed': seed.toJson(),
        'vault': vault.toJson(),
        if (encryptedServers != null)
          'encrypted_servers': encryptedServers!.toJson(),
      };

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
        version: json['version'] as int,
        seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
        vault: EncryptedVault.fromJson(json['vault'] as Map<String, dynamic>),
        encryptedServers: json['encrypted_servers'] != null
            ? EncryptedVault.fromJson(
                json['encrypted_servers'] as Map<String, dynamic>)
            : null,
      );

  String toJsonString() => jsonEncode(toJson());

  factory BackupFile.fromJsonString(String s) =>
      BackupFile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

