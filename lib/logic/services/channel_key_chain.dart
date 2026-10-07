import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../helper_methods.dart';

/// Older channel keys opened from the links rotations leave behind.
///
/// A rotation stores the outgoing key sealed under the incoming one
/// (`CryptoRepository.sealKeyLink`), so a member sealed version n can open
/// n − 1, and so on down to the first rotation that was left unlinked — a
/// channel's opening, or a bot's grant (ARCHITECTURE.md §4, *The key chain*).
/// That is how a newcomer reads a year of history from one or two sealed rows,
/// and why a member's client can drop the rows the chain already covers.
///
/// Its own file because the channel and the push isolate both open keys, and
/// a chain followed two ways is two answers to which key a version is.
class ChannelKeyChain {
  const ChannelKeyChain._();

  /// Fill [keys] downwards through [links], from every version it holds.
  ///
  /// A version this member was sealed a row for ([own]) keeps that row's key:
  /// the link is opened only to check it, and the version is answered when the
  /// two agree. Those are the rows this member could drop. A link that does not
  /// open, or opens to something else, is left alone — a member who mints a
  /// bad one can cost a newcomer their history, but never this member a key
  /// they already hold.
  static Future<Set<int>> follow({
    required CryptoRepository crypto,
    required String channelId,
    required Map<int, Uint8List> keys,
    required List<Map<String, dynamic>> links,
    Set<int> own = const {},
  }) async {
    final confirmed = <int>{};
    // Newest first, so a key opened from one link is there for the next.
    final sorted = [...links]
      ..sort(
        (a, b) => (b['key_version'] as int).compareTo(a['key_version'] as int),
      );
    for (final link in sorted) {
      final version = link['key_version'] as int;
      final newer = keys[version];
      if (newer == null) continue;
      final older = version - 1;
      final held = keys[older];
      if (held != null && !own.contains(older)) continue;
      try {
        final opened = await crypto.openKeyLink(
          newerKey: newer,
          ciphertext: link['ciphertext'] as String,
          nonce: link['nonce'] as String,
          channelId: channelId,
          newerVersion: version,
        );
        if (held == null) {
          keys[older] = opened;
        } else if (_same(opened, held)) {
          confirmed.add(older);
        } else {
          HelperMethods.printDebug(
            '[Keyring] link $version disagrees with the sealed key',
          );
        }
      } catch (e) {
        HelperMethods.printDebug('[Keyring] link $version did not open: $e');
      }
    }
    return confirmed;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
