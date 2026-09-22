part of 'chat_message_list.dart';

/// The messages replies point at that are not in the loaded page: asking the
/// server for them once each, and saying what a quote should draw meanwhile.
mixin _MessageListQuotesMixin on State<ChatMessageList> {
  /// Messages fetched only to render a quote, by id.
  ///
  /// Held here rather than in a cubit because that is what they are: a
  /// rendering answer for this screen, gone when it is, and never part of
  /// the conversation — merging a message from five hundred back into the
  /// list would draw a hole in the history as if it were not there.
  ///
  /// A null value is an answer, not a gap: it means the server said there is
  /// no such row. [_unresolvable] holds the ones it could not tell about, so
  /// a failed lookup is retried when the list next rebuilds and a confirmed
  /// deletion is not asked about again.
  final Map<String, ChatMessage?> _quoted = {};

  /// Lookups in flight, so twenty replies to one message ask once.
  final Set<String> _looking = {};

  /// Ids the last lookup could not settle. Kept apart from [_quoted] so they
  /// stay askable without being answered.
  final Set<String> _unresolvable = {};

  /// Ask about a reference that is not in the list.
  ///
  /// Fired from `build`, which is why it checks so much before doing
  /// anything: a rebuild per keystroke elsewhere must not become a request
  /// per keystroke.
  void _lookUp(String messageId) {
    final lookUp = widget.onLookUpOriginal;
    if (lookUp == null) return;
    if (_quoted.containsKey(messageId) || _looking.contains(messageId)) return;
    _looking.add(messageId);
    unawaited(() async {
      final found = await lookUp(messageId);
      if (!mounted) {
        _looking.remove(messageId);
        return;
      }
      setState(() {
        _looking.remove(messageId);
        if (found.isFound) {
          _quoted[messageId] = found.message;
          _unresolvable.remove(messageId);
        } else if (found.deleted) {
          _quoted[messageId] = null;
          _unresolvable.remove(messageId);
        } else {
          // Not an answer. Left out of the cache so it can be asked again,
          // and recorded so the quote says "unavailable" rather than
          // sitting on "finding it" forever.
          _unresolvable.add(messageId);
        }
      });
    }());
  }

  /// What to draw for a reply's reference, and what pressing it should do.
  ({ReplyOriginState state, ChatMessage? original}) _originOf(
    ChatMessage message,
    Map<String, ChatMessage> byId,
  ) {
    final id = message.replyToId;
    if (id == null) {
      return (state: ReplyOriginState.present, original: null);
    }

    final loaded = byId[id];
    if (loaded != null) {
      return (state: ReplyOriginState.present, original: loaded);
    }
    if (_quoted.containsKey(id)) {
      final fetched = _quoted[id];
      return fetched == null
          ? (state: ReplyOriginState.gone, original: null)
          : (state: ReplyOriginState.behind, original: fetched);
    }
    if (_unresolvable.contains(id) || widget.onLookUpOriginal == null) {
      return (state: ReplyOriginState.unknown, original: null);
    }
    // Asked on the way past. The first frame draws "finding it"; the answer
    // arrives and rebuilds.
    _lookUp(id);
    return (state: ReplyOriginState.looking, original: null);
  }
}
