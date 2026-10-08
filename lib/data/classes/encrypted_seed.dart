import 'package:equatable/equatable.dart';

/// The password-protected master seed blob.
///
/// The master seed is encrypted with AES-256-GCM using a key derived from
/// the user's master password via Argon2id:
///   key = Argon2id(password, salt)
///
/// This blob is generated once at vault creation and stored locally. It is
/// included verbatim in every [BackupFile] export — Argon2id does not need
/// to run again on the same device unless the user changes their password.
class EncryptedSeed extends Equatable {
  final String ciphertext; // base64-encoded AES-GCM ciphertext of masterSeed
  final String iv; // base64-encoded 12-byte nonce
  final String salt; // base64-encoded 32-byte Argon2id salt (unencrypted)

  const EncryptedSeed({
    required this.ciphertext,
    required this.iv,
    required this.salt,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'iv': iv,
    'salt': salt,
  };

  factory EncryptedSeed.fromJson(Map<String, dynamic> json) => EncryptedSeed(
    ciphertext: json['ciphertext'] as String,
    iv: json['iv'] as String,
    salt: json['salt'] as String,
  );

  @override
  List<Object?> get props => [ciphertext, iv, salt];
}
