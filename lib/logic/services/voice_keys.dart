import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

/// Which key a participant's media frames are encrypted with.
///
/// Voice is end-to-end encrypted with the channel's own key — the same key the
/// text keyring distributes, sealed per member and unreadable to the server
/// (ARCHITECTURE.md §4). LiveKit's frame cryptor takes raw bytes, so there is
/// nothing to derive for a person: they use the channel key.
///
/// **A bot does not get that key**, and this is the whole reason the room runs
/// in LiveKit's per-participant key mode rather than its simpler shared-key
/// mode. A shared key would put BOTS.md §2 in the middle of a call: publishing
/// into an encrypted room requires the key, holding the key *is* read access,
/// and "speaks but does not listen" stops being expressible — a music bot would
/// have to be handed the ability to hear every word said in the room.
///
/// So a bot encrypts with [forBot], which every member can compute and no bot
/// can invert:
///
/// ```
/// botKey = HMAC-SHA256(channelKey, "voicebot:v1:<botId>")
/// ```
///
/// Members hold `channelKey`, so they derive the bot's key and hear it. The bot
/// is handed only its own derived key, and HMAC does not run backwards, so it
/// cannot reach `channelKey` and cannot decrypt a single member's audio. It is
/// the shape §2 says a key cannot have, bought by giving the two directions
/// different keys.
class VoiceKeys {
  /// The context string is domain-separated and versioned like everything else
  /// on the ladder (WIRE.md §2). `<botId>` is the bot's `users.id`, so two bots
  /// in one call cannot decrypt each other either.
  static const String botContext = 'voicebot:v1:';

  const VoiceKeys._();

  /// The key [botId] publishes with in a channel whose key is [channelKey].
  static Future<Uint8List> forBot({
    required CryptoRepository crypto,
    required Uint8List channelKey,
    required String botId,
  }) => crypto.hmacSha256(key: channelKey, message: '$botContext$botId');

  /// One bot, and the key it should be sealed in a given channel.
  ///
  /// [isChannelKey] records which of the two kinds it is, because the two are
  /// indistinguishable once wrapped and the database checks the claim against
  /// the listening grant (`009_bot_voice.sql`).
  static Future<SealedBotKey> forOneBot({
    required CryptoRepository crypto,
    required Uint8List channelKey,
    required String botId,
    required bool mayListen,
  }) async {
    // A listener needs the real key — there is no third thing to give it, which
    // is what makes that grant irreversible. A speaker gets the derived one.
    final key = mayListen
        ? channelKey
        : await forBot(crypto: crypto, channelKey: channelKey, botId: botId);
    return SealedBotKey(botId: botId, isChannelKey: mayListen, key: key);
  }

  /// LiveKit addresses keys by a slot in a fixed-size ring, not by our version
  /// number, so the two have to be mapped — and mapped the same way by every
  /// client, or a sender encrypts into a slot its listeners are not reading.
  ///
  /// Modulo the ring size, which is the only mapping that works: a channel that
  /// has rotated more than [ringSize] times has to reuse slots, and reusing the
  /// oldest is what the ring is for. Rotations are rare enough that no two live
  /// versions ever collide.
  static int keyIndex(int keyVersion, {int ringSize = 16}) =>
      keyVersion % ringSize;
}

/// Which key one bot gets in one channel, before it is wrapped.
///
/// Its own type rather than a record so the two booleans in play — "may this
/// bot listen" and "is this the channel key" — cannot be swapped silently at a
/// call site. They are the same fact, and saying so once is the point.
class SealedBotKey {
  final String botId;
  final bool isChannelKey;
  final Uint8List key;

  const SealedBotKey({
    required this.botId,
    required this.isChannelKey,
    required this.key,
  });
}
