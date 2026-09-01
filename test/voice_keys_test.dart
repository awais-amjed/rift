import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_keys.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Which key each participant's media is encrypted with.
///
/// Pure, and therefore reachable without a server, a room, or a call — which is
/// the whole reason this logic lives here rather than inside the keyring. The
/// failure it guards is silent in every other layer: get the key wrong and
/// everybody connects, every track publishes, and nobody hears anyone.
void main() {
  final crypto = CryptoRepository();
  final channelKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
  const botId = '99999999-8888-4777-8666-555555555555';

  group('the key a bot speaks with', () {
    test('is not the channel key', () async {
      // The whole property in one assertion. If these were ever equal, a bot
      // could decrypt every member in the room and nothing else would notice.
      final derived = await VoiceKeys.forBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: botId,
      );
      expect(derived, isNot(equals(channelKey)));
      expect(derived.length, 32);
    });

    test('is different for every bot, so two cannot read each other', () async {
      final a = await VoiceKeys.forBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: botId,
      );
      final b = await VoiceKeys.forBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: '11111111-2222-4333-8444-555555555555',
      );
      expect(a, isNot(equals(b)));
    });

    test('moves when the channel key rotates', () async {
      // Otherwise a bot removed from a channel by rotation would keep a working
      // key, which is the one thing rotation exists to prevent.
      final rotated = Uint8List.fromList(List.generate(32, (i) => i + 2));
      final before = await VoiceKeys.forBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: botId,
      );
      final after = await VoiceKeys.forBot(
        crypto: crypto,
        channelKey: rotated,
        botId: botId,
      );
      expect(before, isNot(equals(after)));
    });
  });

  group('which key one bot is sealed', () {
    test('a bot that may only speak gets the derived one', () async {
      final sealed = await VoiceKeys.forOneBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: botId,
        mayListen: false,
      );
      expect(sealed.isChannelKey, isFalse);
      expect(sealed.key, isNot(equals(channelKey)));
    });

    test('a bot that may listen gets the channel key itself', () async {
      // There is no third thing to give a listener, which is exactly why that
      // grant cannot be taken back (BOTS.md §6b).
      final sealed = await VoiceKeys.forOneBot(
        crypto: crypto,
        channelKey: channelKey,
        botId: botId,
        mayListen: true,
      );
      expect(sealed.isChannelKey, isTrue);
      expect(sealed.key, equals(channelKey));
    });

    test('the flag always matches the key it describes', () async {
      // The database checks `is_channel_key` against the listening grant, and
      // it cannot see inside the ciphertext. A caller that set the flag one way
      // and sealed the other would make the grant mean one thing in the UI and
      // another in the room.
      for (final mayListen in [true, false]) {
        final sealed = await VoiceKeys.forOneBot(
          crypto: crypto,
          channelKey: channelKey,
          botId: botId,
          mayListen: mayListen,
        );
        expect(sealed.isChannelKey, mayListen);
        expect(sealed.key == channelKey, mayListen);
      }
    });
  });

  group('which slot a key goes in', () {
    test('follows the version, so clients agree without talking', () {
      expect(VoiceKeys.keyIndex(1), 1);
      expect(VoiceKeys.keyIndex(15), 15);
    });

    test('wraps around the ring rather than running off the end', () {
      // LiveKit's ring is fixed-size. A version past it has to reuse the oldest
      // slot; rotations are rare enough that no two live versions collide.
      expect(VoiceKeys.keyIndex(16), 0);
      expect(VoiceKeys.keyIndex(17), 1);
      expect(VoiceKeys.keyIndex(33), 1);
    });

    test('a channel with no key yet maps to slot 0', () {
      expect(VoiceKeys.keyIndex(0), 0);
    });
  });
}
