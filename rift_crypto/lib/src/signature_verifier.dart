import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Checks one Ed25519 signature: every message opened, every row read.
///
/// Its own seam because where the work runs is the whole difference. A page
/// of checks in pure Dart held a phone's UI thread for about 210 ms of a
/// 0.33 s channel open (Nov 12 2026). [DartSignatureVerifier] is the
/// reference and what the web uses (the `cryptography` package hands it to
/// Web Crypto there); the app installs one backed by its Rust library
/// everywhere else, through [CryptoRepository.signatureVerifier].
abstract interface class SignatureVerifier {
  /// Whether [signature] (64 bytes) over [message] is [publicKey]'s
  /// (32 bytes). False, never a throw, for anything malformed.
  Future<bool> verify({
    required List<int> message,
    required Uint8List signature,
    required Uint8List publicKey,
  });
}

/// [SignatureVerifier] in Dart, with the `cryptography` package.
class DartSignatureVerifier implements SignatureVerifier {
  const DartSignatureVerifier();

  @override
  Future<bool> verify({
    required List<int> message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    if (publicKey.length != 32 || signature.length != 64) return false;
    return Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }
}
