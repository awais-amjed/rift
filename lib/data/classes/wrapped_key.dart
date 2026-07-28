/// A symmetric key sealed to one recipient's X25519 public key
/// (ephemeral-static Diffie-Hellman, "sealed box" style) — the stored shape
/// of a channel-keyring entry (ARCHITECTURE.md §4, Design 2).
///
/// Self-contained: unwrapping needs only the recipient's private key, so the
/// wrapper's identity doesn't matter for decryption (authenticity of keyring
/// entries is established by an Ed25519 signature at the row level, not here).
class WrappedKey {
  /// Ephemeral X25519 public key generated for this wrap, base64.
  final String ephemeralPublicKey;

  /// AES-256-GCM ciphertext + auth tag of the wrapped key, base64.
  final String ciphertext;

  /// AES-GCM nonce, base64.
  final String nonce;

  const WrappedKey({
    required this.ephemeralPublicKey,
    required this.ciphertext,
    required this.nonce,
  });

  factory WrappedKey.fromJson(Map<String, dynamic> json) {
    return WrappedKey(
      ephemeralPublicKey: json['ephemeral_public_key'] as String,
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'ephemeral_public_key': ephemeralPublicKey,
    'ciphertext': ciphertext,
    'nonce': nonce,
  };
}
