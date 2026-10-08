import 'package:equatable/equatable.dart';

/// Encrypted vault blob containing the joined-servers list.
///
/// Encrypted with AES-256-GCM using a key derived from the master seed:
///   key = HMAC-SHA256(masterSeed, "vault:v1")
///
/// Because the key is always derivable from the locally-stored master seed,
/// this blob can be silently re-encrypted on every state change — no password
/// needed. The password layer lives in [EncryptedSeed] instead.
class EncryptedVault extends Equatable {
  final String ciphertext; // base64-encoded AES-GCM ciphertext
  final String iv; // base64-encoded 12-byte nonce

  const EncryptedVault({required this.ciphertext, required this.iv});

  Map<String, dynamic> toJson() => {'ciphertext': ciphertext, 'iv': iv};

  factory EncryptedVault.fromJson(Map<String, dynamic> json) => EncryptedVault(
    ciphertext: json['ciphertext'] as String,
    iv: json['iv'] as String,
  );

  @override
  List<Object?> get props => [ciphertext, iv];
}
