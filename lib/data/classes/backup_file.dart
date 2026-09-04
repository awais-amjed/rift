import 'dart:convert';

import 'encrypted_seed.dart';
import 'encrypted_vault.dart';

/// Portable backup file combining the encrypted master seed and vault metadata.
///
/// File layout (JSON):
/// ```
///   seed             → AES-GCM( Argon2id(password, salt),      masterSeed )
///   recovery         → AES-GCM( Argon2id(recoveryKey, salt2),   masterSeed )
///   vault            → AES-GCM( HMAC(masterSeed, "vault:v1"), joined_servers )
///   encryptedServers → AES-GCM( HMAC(masterSeed, "vault:v1"), servers JSON )
/// ```
///
/// `seed` and `recovery` hold the *same* master seed under two independent
/// keys. That is the point of the second one: a forgotten password costs you
/// the first blob and nothing else.
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
  /// v3 added [recovery]. Older files still load — [recovery] is null and the
  /// password is the only way in, which is exactly what those files meant.
  static const int currentVersion = 3;

  final int version;
  final EncryptedSeed seed;
  final EncryptedVault vault;

  /// AES-GCM encrypted JSON array of full server metadata.
  /// Key = HMAC(masterSeed, "vault:v1") — same key as [vault], separate IV.
  /// Each entry: id, name, iconUrl, supabaseUrl, supabaseKey, livekitUrl,
  /// keyVersion. Token is intentionally excluded.
  final EncryptedVault? encryptedServers;

  /// The master seed again, wrapped under the recovery key instead of the
  /// password. Null on backups written before recovery keys existed, and on
  /// accounts whose key was never generated.
  final EncryptedSeed? recovery;

  const BackupFile({
    required this.version,
    required this.seed,
    required this.vault,
    this.encryptedServers,
    this.recovery,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'seed': seed.toJson(),
    'vault': vault.toJson(),
    if (encryptedServers != null)
      'encrypted_servers': encryptedServers!.toJson(),
    if (recovery != null) 'recovery': recovery!.toJson(),
  };

  factory BackupFile.fromJson(Map<String, dynamic> json) => BackupFile(
    version: json['version'] as int,
    seed: EncryptedSeed.fromJson(json['seed'] as Map<String, dynamic>),
    vault: EncryptedVault.fromJson(json['vault'] as Map<String, dynamic>),
    encryptedServers: json['encrypted_servers'] != null
        ? EncryptedVault.fromJson(
            json['encrypted_servers'] as Map<String, dynamic>,
          )
        : null,
    recovery: json['recovery'] != null
        ? EncryptedSeed.fromJson(json['recovery'] as Map<String, dynamic>)
        : null,
  );

  String toJsonString() => jsonEncode(toJson());

  factory BackupFile.fromJsonString(String s) =>
      BackupFile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
