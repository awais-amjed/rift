import 'dart:async';

import '../../data/classes/api_response.dart';
import '../../data/classes/chat_message.dart';

/// What came back when a client went looking for the message a reply names.
///
/// Three outcomes, not two, and keeping them apart is the whole point of the
/// type. "I could not find it" and "it is not there" are different facts
/// about the world, and a reader told the second when the first is true has
/// been informed that somebody deleted something they did not
/// (ARCHITECTURE.md §4 makes the same distinction one level down, between a
/// message that is locked and one that was dropped).
class QuotedMessage {
  /// The message, when there is one to show.
  final ChatMessage? message;

  /// The server answered, and there is no such row. Somebody deleted it.
  final bool deleted;

  /// It is real and readable, just not in the page the reader has loaded.
  const QuotedMessage.found(ChatMessage this.message) : deleted = false;

  /// Asked, and told there is nothing there.
  const QuotedMessage.deleted() : message = null, deleted = true;

  /// Could not tell: the request failed, the conversation moved on, or the
  /// row came back and did not verify. Nothing is claimed.
  const QuotedMessage.unknown() : message = null, deleted = false;

  bool get isFound => message != null;

  /// What a lookup's [response] means, once [open] has turned its row into a
  /// message.
  ///
  /// Shared by every conversation that can quote — a channel, a server DM, a
  /// central DM — which fetch and open a row each in their own way but read
  /// the answer by one rule. [stillOpen] is asked *after* the request: an
  /// answer about a conversation the reader has since left is not one.
  static Future<QuotedMessage> settle(
    APIResponse response, {
    required bool Function() stillOpen,
    required Future<ChatMessage?> Function(Map<String, dynamic> row) open,
  }) async {
    if (!response.success || !stillOpen()) return const QuotedMessage.unknown();
    final row = (response.data as Map<String, dynamic>)['message'];
    if (row == null) return const QuotedMessage.deleted();
    final message = await open((row as Map).cast<String, dynamic>());
    return message == null
        ? const QuotedMessage.unknown()
        : QuotedMessage.found(message);
  }

  /// [settle] for a batch: what one read of several ids, `{messages: […]}`,
  /// says about each of [ids].
  ///
  /// An id the answer has no row for is [QuotedMessage.deleted], as a
  /// single read's `{message: null}` was; one whose row [open] did not turn
  /// into a message is [QuotedMessage.unknown].
  static Future<Map<String, QuotedMessage>> settleMany(
    APIResponse response, {
    required List<String> ids,
    required bool Function() stillOpen,
    required Future<List<ChatMessage>> Function(List<Map<String, dynamic>> rows)
    open,
  }) async {
    const unknown = QuotedMessage.unknown();
    if (!response.success || !stillOpen()) {
      return {for (final id in ids) id: unknown};
    }
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .map((r) => (r as Map).cast<String, dynamic>())
        .toList();
    final present = {for (final r in rows) '${r['id']}'};
    final opened = {for (final m in await open(rows)) m.id: m};
    return {
      for (final id in ids)
        id: opened[id] != null
            ? QuotedMessage.found(opened[id]!)
            : present.contains(id)
            ? unknown
            : const QuotedMessage.deleted(),
    };
  }
}

/// Quote lookups made together, asked together.
///
/// A list asks about each reply's original as it builds the row, so a page
/// with ten replies to older messages asked ten single-row reads. Lookups
/// made in the same turn of the event loop — one frame's rows — are held
/// until it ends and sent as one read per conversation [K], in chunks of
/// [chunk]. Each caller still gets its own answer.
class QuoteBatcher<K> {
  QuoteBatcher(this._fetch, {this.chunk = 100});

  /// What one read says about each id it was asked, for conversation [K].
  final Future<Map<String, QuotedMessage>> Function(K key, List<String> ids)
  _fetch;

  final int chunk;

  final Map<K, Map<String, Completer<QuotedMessage>>> _waiting = {};
  bool _scheduled = false;

  Future<QuotedMessage> lookUp(K key, String id) {
    final forKey = _waiting.putIfAbsent(key, () => {});
    final waiting = forKey[id];
    if (waiting != null) return waiting.future;
    final completer = Completer<QuotedMessage>();
    forKey[id] = completer;
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  void _flush() {
    _scheduled = false;
    final batches = Map.of(_waiting);
    _waiting.clear();
    for (final MapEntry(key: key, value: waiting) in batches.entries) {
      final ids = waiting.keys.toList();
      for (var i = 0; i < ids.length; i += chunk) {
        final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
        unawaited(_answer(key, part, waiting));
      }
    }
  }

  Future<void> _answer(
    K key,
    List<String> ids,
    Map<String, Completer<QuotedMessage>> waiting,
  ) async {
    Map<String, QuotedMessage> answers;
    try {
      answers = await _fetch(key, ids);
    } catch (_) {
      answers = const {};
    }
    for (final id in ids) {
      waiting[id]!.complete(answers[id] ?? const QuotedMessage.unknown());
    }
  }
}

/// Messages a change doorbell named that are not in the loaded page.
///
/// A conversation re-reads a changed message only when it is on the page
/// ([refreshMessage] in each chat cubit). One further back can still be
/// drawn, as the quote of a reply on the page, from a copy the list fetched
/// once — so the cubit says which message changed, and the list asks for any
/// quote of it again. Without this an edited or deleted message kept its old
/// words in every quote of it until the conversation was opened again.
class OffPageChanges {
  final StreamController<String> _changes = StreamController.broadcast();

  /// The ids, as they are rung.
  Stream<String> get stream => _changes.stream;

  void ring(String messageId) {
    if (!_changes.isClosed) _changes.add(messageId);
  }

  Future<void> close() => _changes.close();
}
