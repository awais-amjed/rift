part of 'channel_chat_cubit.dart';

/// What the bar above the message box holds: the channel's open polls and its
/// bots' live panels, wherever they sit in its history.
///
/// The server is asked once the channel opens and again when its feed comes
/// back (`channel_live_messages`). Between those, every emit that changes the
/// loaded page merges it in again ([_withLive]), so a poll posted or a panel
/// redrawn on the page reaches the bar with no request of its own. A server
/// from before the read answers with an error, and the bar is the page's.
mixin _ChannelChatLiveMixin
    on
        Cubit<ChannelChatState>,
        _ChannelChatRowsMixin,
        _ChannelChatSavedMixin,
        _ChannelChatHistoryMixin {
  /// The server's last answer, decrypted. Null before it has one, or when it
  /// could not give one.
  List<ChatMessage>? _liveFromServer;

  /// [_liveFromServer] changed under an emit that may not touch the page.
  bool _liveStale = false;

  /// Ask the server what is live in the open channel.
  Future<void> refreshLive() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    final response = await _channelMessages.listLiveMessages(
      channelId: channelId,
    );
    if (isClosed || state.channelId != channelId) return;
    if (!response.success) {
      HelperMethods.printDebug('[Chat] live read failed: ${response.error}');
      return;
    }
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    final decrypted = await _decryptRows(channelId, rows);
    if (isClosed || state.channelId != channelId) return;
    _liveFromServer = decrypted;
    _liveStale = true;
    emit(state);
  }

  /// A row the bar holds was re-read: [message] is its new copy, or null when
  /// it was deleted.
  @override
  void _updateLive(String messageId, ChatMessage? message) {
    final held = _liveFromServer;
    if (held == null || !held.any((m) => m.id == messageId)) return;
    _liveFromServer = [
      for (final m in held)
        if (m.id != messageId) m else ?message,
    ];
    _liveStale = true;
  }

  /// Forget the open channel's answer, for the next channel to ask its own.
  void _clearLive() {
    _liveFromServer = null;
    _liveStale = false;
  }

  /// [next] with [ChannelChatState.live] brought up to date. Kept as the same
  /// list while it says the same, so the bar's selector sees no change when a
  /// keystroke or an upload tick moves the page.
  ChannelChatState _withLive(ChannelChatState next) {
    if (!_liveStale && identical(next.messages, state.messages)) return next;
    _liveStale = false;
    final merged = LiveItems.merge(
      fromServer: _liveFromServer,
      loaded: next.messages,
    );
    if (listEquals(merged, next.live)) return next;
    return next.copyWith(live: merged);
  }
}
