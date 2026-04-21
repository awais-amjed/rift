import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../repositories/crypto_repository.dart';

/// Result of deriving a server-specific cryptographic identity.
class ServerIdentity {
  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;
  final String stableId; // base64-encoded

  const ServerIdentity({
    required this.keyPair,
    required this.publicKeyBytes,
    required this.stableId,
  });

  /// The public key as a base64 string (sent to the server).
  String get publicKeyBase64 => CryptoRepository.toBase64(publicKeyBytes);
}

