import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../src/rust/api/signatures.dart' as rust;

/// [SignatureVerifier] on the Rust library, on one of the bridge's worker
/// threads instead of the UI isolate. It answers as [DartSignatureVerifier]
/// does for every signature an honest key made; it also refuses a key of
/// small order, as the browser's Web Crypto does.
///
/// Installed by `AppBootstrap` once the bridge is up; not on the web, which
/// has no bridge and whose Dart path already runs on Web Crypto.
class NativeSignatureVerifier implements SignatureVerifier {
  const NativeSignatureVerifier();

  @override
  Future<bool> verify({
    required List<int> message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) => rust.verifyEd25519(
    publicKey: publicKey,
    signature: signature,
    message: message,
  );
}
