part of 'crypto_repository.dart';

// ── Remembered signatures ──────────────────────────

/// Whether [signature] over [message] is [publicKey]'s, checking each exact
/// triple once per run.
///
/// Opening a channel checks every row twice, first in the saved copy and then
/// in the server's page, and checks them all again on every later open. In
/// pure Dart each check costs a few milliseconds even in a release build, so a
/// page of them held the main thread long enough to drop frames, and in a debug
/// build long enough for Android to report the app not responding. A triple
/// that passed once passes for ever, so only passes are remembered, under a
/// SHA-256 of all three. The key and signature have fixed lengths, so no two
/// different triples hash the same input. A failure is never remembered: a
/// forged row is rare, and checking it again costs nothing that matters.
Future<bool> _verifyEd25519({
  required List<int> message,
  required Uint8List signature,
  required Uint8List publicKey,
}) async {
  final remembered = _VerifiedSignatures.keyOf(message, signature, publicKey);
  if (remembered != null && _VerifiedSignatures.contains(remembered)) {
    return true;
  }
  final valid = await Ed25519().verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (valid && remembered != null) _VerifiedSignatures.add(remembered);
  return valid;
}

/// The triples that passed, newest last, in memory only. Never saved: a
/// remembered pass is only as trustworthy as the process that checked it.
abstract final class _VerifiedSignatures {
  /// Several full pages of every channel and conversation opened in a run, at
  /// 32 bytes each.
  static const _capacity = 8192;

  static final _passed = <String>{};

  /// Null when the lengths are not Ed25519's: such a check fails anyway, and
  /// the fixed lengths are what keep the hash's input unambiguous.
  static String? keyOf(
    List<int> message,
    Uint8List signature,
    Uint8List publicKey,
  ) {
    if (publicKey.length != 32 || signature.length != 64) return null;
    final input = Uint8List(96 + message.length)
      ..setAll(0, publicKey)
      ..setAll(32, signature)
      ..setAll(96, message);
    return String.fromCharCodes(const DartSha256().hashSync(input).bytes);
  }

  static bool contains(String key) {
    // Moved to the newest end, so what is still being read stays.
    if (!_passed.remove(key)) return false;
    _passed.add(key);
    return true;
  }

  static void add(String key) {
    _passed.add(key);
    if (_passed.length > _capacity) _passed.remove(_passed.first);
  }
}
