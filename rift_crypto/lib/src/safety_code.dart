import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

/// The number two people read to each other to check that nobody is standing
/// between them.
///
/// Both devices compute the same sixty digits from the two published chat
/// keys and the two user ids, so a server that handed one side a key of its
/// own making cannot make the two halves agree. Reading them aloud — or
/// comparing the QR the app draws from them — is the whole check.
///
/// The shape is Signal's, and the reasons are Signal's too:
///
/// - **Both keys, in a fixed order.** Sorted by the digits themselves rather
///   than by who is asking, so the code does not depend on which device it is
///   read from.
/// - **Iterated hashing.** [_rounds] passes of SHA-256 makes searching for a
///   key whose digits happen to match somebody else's expensive, where a
///   single hash would be a few seconds of GPU time per try.
/// - **Digits, not hex.** They are read aloud over a call, and a-f are the
///   letters people mishear — and reading them is the whole check, since
///   nothing here scans anything.
///
/// It covers the key messages are *sealed* to. It does not yet cover the
/// signing key an envelope is signed with — a server member row does not
/// carry one — so a verified code says "only they can read this", and does
/// not yet say "only they could have written it".
class SafetyCode {
  const SafetyCode._();

  /// Signal uses 5200. The same order, and a few milliseconds on a phone.
  static const int _rounds = 5200;

  /// Digits per person. Two of them make the sixty a pair reads.
  static const int _digitsEach = 30;

  /// Five digits at a time, which is the longest group people read back
  /// without losing their place.
  static const int groupSize = 5;

  /// Rift's own, so a code can never be replayed as another app's.
  static const String _domain = 'rift-safety-code-v1';

  /// The sixty digits for a pair, identical on both devices.
  ///
  /// [myKey] and [theirKey] are base64 X25519 public keys as published;
  /// the ids are the two user ids on that tier.
  static String between({
    required String myKey,
    required String myId,
    required String theirKey,
    required String theirId,
  }) {
    final mine = _half(myKey, myId);
    final theirs = _half(theirKey, theirId);
    // Sorted by the digits, not by who is asking.
    return (mine.compareTo(theirs) <= 0) ? '$mine$theirs' : '$theirs$mine';
  }

  /// [code] in groups of [groupSize], for reading aloud.
  static List<String> groups(String code) => [
    for (var i = 0; i < code.length; i += groupSize)
      code.substring(
        i,
        i + groupSize > code.length ? code.length : i + groupSize,
      ),
  ];

  /// One person's thirty digits: their published key, bound to their id.
  static String _half(String keyBase64, String id) {
    final seed = utf8.encode('$_domain|$id|$keyBase64');
    const sha256 = DartSha256();
    var digest = Uint8List.fromList(sha256.hashSync(seed).bytes);
    for (var i = 1; i < _rounds; i++) {
      digest = Uint8List.fromList(sha256.hashSync([...digest, ...seed]).bytes);
    }

    final buffer = StringBuffer();
    for (var i = 0; buffer.length < _digitsEach; i++) {
      // Five bytes a group, read big-endian and taken modulo 100000: the
      // remainder is flat enough over 2^40 that the bias is far below what
      // matters to a code this long.
      final offset = i * 5;
      var value = 0;
      for (var b = 0; b < 5; b++) {
        value = (value << 8) | digest[(offset + b) % digest.length];
      }
      buffer.write((value % 100000).toString().padLeft(groupSize, '0'));
    }
    return buffer.toString().substring(0, _digitsEach);
  }
}
