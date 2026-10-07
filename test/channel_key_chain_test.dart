import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/channel_key_chain.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// The key chain (ARCHITECTURE.md §4): each channel key version sealed under
/// the next. A link that opens anywhere but its own place would hand a key to
/// the wrong version, and a chain that overrode a key a member was sealed would
/// let one bad link take their history away.
void main() {
  final crypto = CryptoRepository();
  const channel = 'c0ffee00-0000-4000-8000-000000000001';

  Future<Map<String, dynamic>> link(
    Uint8List newer,
    Uint8List older,
    int newerVersion, {
    String channelId = channel,
  }) async {
    final sealed = await crypto.sealKeyLink(
      newerKey: newer,
      olderKey: older,
      channelId: channelId,
      newerVersion: newerVersion,
    );
    return {
      'key_version': newerVersion,
      'ciphertext': sealed.ciphertext,
      'nonce': sealed.nonce,
    };
  }

  group('key links', () {
    test('open to the older key under the newer one', () async {
      final v1 = crypto.generateChannelKey();
      final v2 = crypto.generateChannelKey();
      final l = await link(v2, v1, 2);
      final opened = await crypto.openKeyLink(
        newerKey: v2,
        ciphertext: l['ciphertext'] as String,
        nonce: l['nonce'] as String,
        channelId: channel,
        newerVersion: 2,
      );
      expect(opened, v1);
    });

    test('do not open under another key, channel or version', () async {
      final v1 = crypto.generateChannelKey();
      final v2 = crypto.generateChannelKey();
      final l = await link(v2, v1, 2);
      Future<Uint8List> open(Uint8List key, String channelId, int version) =>
          crypto.openKeyLink(
            newerKey: key,
            ciphertext: l['ciphertext'] as String,
            nonce: l['nonce'] as String,
            channelId: channelId,
            newerVersion: version,
          );
      await expectLater(open(v1, channel, 2), throwsA(anything));
      await expectLater(
        open(v2, 'c0ffee00-0000-4000-8000-000000000002', 2),
        throwsA(anything),
      );
      await expectLater(open(v2, channel, 3), throwsA(anything));
    });
  });

  group('ChannelKeyChain.follow', () {
    test('opens every version down to the first unlinked rotation', () async {
      final k = [for (var i = 0; i < 5; i++) crypto.generateChannelKey()];
      // Versions 1–4; 2 was a bot's grant, so nothing links 2 down to 1.
      final links = [await link(k[4], k[3], 4), await link(k[3], k[2], 3)];
      final keys = {4: k[4]};
      final confirmed = await ChannelKeyChain.follow(
        crypto: crypto,
        channelId: channel,
        keys: keys,
        links: links,
      );
      expect(keys[3], k[3]);
      expect(keys[2], k[2]);
      expect(keys.containsKey(1), isFalse);
      expect(confirmed, isEmpty);
    });

    test('answers the sealed rows a link agrees with', () async {
      final v1 = crypto.generateChannelKey();
      final v2 = crypto.generateChannelKey();
      final keys = {1: v1, 2: v2};
      final confirmed = await ChannelKeyChain.follow(
        crypto: crypto,
        channelId: channel,
        keys: keys,
        links: [await link(v2, v1, 2)],
        own: {1, 2},
      );
      expect(confirmed, {1});
    });

    test('a bad link never replaces a sealed key, nor confirms it', () async {
      final v1 = crypto.generateChannelKey();
      final v2 = crypto.generateChannelKey();
      final forged = await link(v2, crypto.generateChannelKey(), 2);
      final keys = {1: v1, 2: v2};
      final confirmed = await ChannelKeyChain.follow(
        crypto: crypto,
        channelId: channel,
        keys: keys,
        links: [forged],
        own: {1, 2},
      );
      expect(keys[1], v1);
      expect(confirmed, isEmpty);
    });

    test('a link that does not open is skipped, not fatal', () async {
      final v2 = crypto.generateChannelKey();
      final keys = {2: v2};
      final confirmed = await ChannelKeyChain.follow(
        crypto: crypto,
        channelId: channel,
        keys: keys,
        links: [
          await link(crypto.generateChannelKey(), crypto.generateChannelKey(), 2),
        ],
      );
      expect(keys.keys, [2]);
      expect(confirmed, isEmpty);
    });
  });
}
