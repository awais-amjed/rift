import 'dart:async';
import 'dart:math';

import '../../logic/services/broadcast_payload.dart';
import '../../logic/services/server_topics.dart';
import '../classes/bot_suggestion.dart';
import '../classes/server_member.dart';
import '../repositories/session_repository.dart';

/// Asking a bot what to offer while one of its commands is typed — the songs
/// under `/play thats so tr` (WIRE.md §7).
///
/// Both halves are Realtime broadcasts and nothing is stored: the request
/// goes to the bot's own topic, which any co-member may send to and only the
/// bot hears, and the answer comes back on this person's. Holds nothing
/// between calls, so a widget builds one from the session.
class BotSuggestionsApi {
  final SessionRepository _session;

  BotSuggestionsApi({required SessionRepository session}) : _session = session;

  /// Long enough for a bot that searches somewhere slow; short enough that a
  /// bot that is not running does not leave a "Searching…" row up for good.
  static const Duration timeout = Duration(seconds: 6);

  static final Random _rng = Random.secure();

  /// What [bot] offers for `/<command> <text>` in [channelId] on the selected
  /// server — empty when it offers nothing, does not answer in time, or the
  /// server is gone.
  Future<List<BotSuggestion>> ask({
    required String channelId,
    required ServerMember bot,
    required String command,
    required String text,
  }) async {
    final server = _session.selectedServer;
    final me = server?.user?.id;
    if (server == null || me == null) return const [];
    final realtime = _session.realtime;

    // Held only for this request. The chat already holds this topic, so this
    // is a share of a join that exists rather than a new one.
    final own = realtime.join(server, ServerTopics.user(me));
    if (own == null) return const [];
    final id = _newId();
    final answered = Completer<List<BotSuggestion>>();
    own.onBroadcast(ServerEvent.botSuggestions, (payload) {
      if (answered.isCompleted) return;
      // Nested under `payload` as the socket delivers it.
      final rows = BotSuggestion.fromAnswer(
        BroadcastPayload.of(payload),
        id: id,
        botId: bot.id,
      );
      if (rows != null) answered.complete(rows);
    });
    try {
      await realtime
          .ring(server, ServerTopics.user(bot.id), ServerEvent.botSuggest, {
            'v': 1,
            'id': id,
            'from': me,
            'channel': channelId,
            'command': command,
            'text': text,
          });
      return await answered.future.timeout(timeout, onTimeout: () => const []);
    } finally {
      await own.release();
    }
  }

  /// 16 characters from the request id's alphabet: unguessable, which is the
  /// whole of what makes an answer naming it the bot's (WIRE.md §7).
  static String _newId() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    return String.fromCharCodes([
      for (var i = 0; i < 16; i++)
        alphabet.codeUnitAt(_rng.nextInt(alphabet.length)),
    ]);
  }
}
