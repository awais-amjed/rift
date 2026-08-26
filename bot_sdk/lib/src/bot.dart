import 'dart:async';

import 'package:rift/data/classes/message_envelope.dart';

import 'bot_session.dart';

/// One command, as the bot receives it.
class BotMessage {
  final int id;
  final String channelId;
  final String senderId;

  /// The whole line the member typed, slash included. The SDK does not split
  /// arguments, because only the bot knows what its arguments mean.
  final String text;

  const BotMessage({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.text,
  });

  /// The verb, lower-cased and without the slash — `/Play a song` → `play`.
  String get command {
    final body = text.trim();
    if (!body.startsWith('/')) return '';
    final end = body.indexOf(RegExp(r'\s'));
    return (end == -1 ? body.substring(1) : body.substring(1, end))
        .toLowerCase();
  }

  /// Everything after the verb, trimmed. Empty for a bare command.
  String get arguments {
    final body = text.trim();
    final end = body.indexOf(RegExp(r'\s'));
    return end == -1 ? '' : body.substring(end).trim();
  }
}

/// A running bot: poll for commands, answer them.
///
/// **It only ever sees what it was addressed.** That is not this class being
/// careful — `messages_select` will not return anything else, so a bug here
/// cannot widen it. What the class does is save you writing the same two
/// queries and the same signature every time.
class Bot {
  final BotSession session;

  /// How often to look for new commands.
  ///
  /// Polling rather than Realtime, deliberately, for the first version: it has
  /// no reconnect logic to get wrong, no tenant event budget to spend (a
  /// self-hosted server's is ~100/second and shared with every member's
  /// badges), and a bot answering a second late is a bot answering. Realtime
  /// belongs here eventually; it does not belong in the version that has to
  /// prove the rest works.
  final Duration poll;

  Bot(this.session, {this.poll = const Duration(seconds: 2)});

  int _lastSeen = 0;
  Timer? _timer;

  /// Start answering. [onCommand] is called once per command, in id order.
  ///
  /// Starts from *now*: a bot restarting does not replay a backlog of commands
  /// people gave up on minutes ago and act on all of them at once.
  Future<void> listen(FutureOr<void> Function(BotMessage) onCommand) async {
    await session.login();
    _lastSeen = await _newestId();
    _timer = Timer.periodic(poll, (_) => _drain(onCommand));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _drain(FutureOr<void> Function(BotMessage) onCommand) async {
    try {
      final rows = await session.select(
        'messages?select=id,channel_id,sender_id,ciphertext'
        '&to_bot=eq.${session.userId}&id=gt.$_lastSeen&order=id.asc',
      );
      for (final row in rows) {
        _lastSeen = row['id'] as int;
        await onCommand(
          BotMessage(
            id: row['id'] as int,
            channelId: row['channel_id'] as String,
            senderId: row['sender_id'] as String,
            text: row['ciphertext'] as String? ?? '',
          ),
        );
      }
    } on BotException {
      // A session expires an hour after it was minted, and the only recovery
      // is the one that needs no state: sign again with the key the seed
      // derives. Swallowing the tick is right — the next one retries, and the
      // commands are still in the database waiting.
      await session.login();
    }
  }

  Future<int> _newestId() async {
    final rows = await session.select(
      'messages?select=id&to_bot=eq.${session.userId}&order=id.desc&limit=1',
    );
    return rows.isEmpty ? 0 : rows.first['id'] as int;
  }

  /// Answer in the channel, where everybody can see it.
  ///
  /// For output that is genuinely public — a poll result, a dice roll. For
  /// anything the room does not need, use [replyPrivately]; for living state
  /// like a queue, a panel is the right shape and is not built yet.
  Future<void> reply(BotMessage to, String text) =>
      _post(to, text, ephemeralFor: null);

  /// Answer only the person who asked.
  ///
  /// Errors, confirmations, and anything that would be noise to everyone else.
  /// The row never reaches another member — `messages_select` enforces it, so
  /// this is genuinely private from the channel rather than hidden by clients
  /// agreeing to hide it.
  Future<void> replyPrivately(BotMessage to, String text) =>
      _post(to, text, ephemeralFor: to.senderId);

  /// Signed but not sealed, which is the whole shape of a bot's message.
  ///
  /// Not sealed: a bot holds no channel key and never will, so a sealed reply
  /// is one its readers would have to open with a key it could not have used.
  /// Signed: the reply carries the bot's name in a room full of people, and
  /// clients drop what they cannot verify. An unsigned reply is an invisible
  /// one.
  Future<void> _post(
    BotMessage to,
    String text, {
    required String? ephemeralFor,
  }) async {
    final identity = await session.identity();
    final envelope = await session.crypto.signPlaintext(
      plaintext: text,
      signingKeyPair: identity.keyPair,
      contextId: to.channelId,
    );
    await session.insert('messages', {
      'channel_id': to.channelId,
      ...envelope.toJson(),
      'reply_to': to.id,
      if (ephemeralFor != null) 'ephemeral_for': ephemeralFor,
    });
  }
}

/// Re-exported so a bot can sign something itself without reaching past the
/// SDK for the app's internals.
typedef Envelope = MessageEnvelope;
