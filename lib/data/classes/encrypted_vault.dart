/// Represents the encrypted vault blob, ready for local storage or cloud sync.
///
/// All byte fields are stored as base64-encoded strings for easy serialization.
class EncryptedVault {
  final String ciphertext; // base64-encoded AES-GCM ciphertext
  final String iv; // base64-encoded 12-byte IV
  final String globalSalt; // base64-encoded 32-byte salt (unencrypted)

  const EncryptedVault({
    required this.ciphertext,
    required this.iv,
    required this.globalSalt,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertext,
        'iv': iv,
        'global_salt': globalSalt,
      };

  factory EncryptedVault.fromJson(Map<String, dynamic> json) => EncryptedVault(
        ciphertext: json['ciphertext'] as String,
        iv: json['iv'] as String,
        globalSalt: json['global_salt'] as String,
      );
}

