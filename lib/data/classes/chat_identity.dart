import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../repositories/crypto_repository.dart';

/// Result of deriving a host-specific chat encryption identity (X25519).
///
/// Parallel to [ServerIdentity] (Ed25519, auth) but for E2E message
/// encryption — see ARCHITECTURE.md §4. Derived from the master seed, so the
/// backup format needs no changes.
class ChatIdentity {
  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  const ChatIdentity({required this.keyPair, required this.publicKeyBytes});

  /// The public key as a base64 string (published to the server).
  String get publicKeyBase64 => CryptoRepository.toBase64(publicKeyBytes);
}
