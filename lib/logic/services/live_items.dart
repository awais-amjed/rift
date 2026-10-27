import '../../data/classes/chat_message.dart';

/// What the bar above a channel's message box holds, decided from rows the
/// chat already has.
///
/// The server's answer (`channel_live_messages`) finds what is live however
/// far back it was posted; the loaded page holds the freshest copy of what it
/// has, and is all there is on a server from before that read.
class LiveItems {
  const LiveItems._();

  /// Could this row belong in the bar? Its time is asked later
  /// ([openPolls]): a poll that closed is still a poll.
  static bool _isCandidate(ChatMessage message) => message.poll != null;

  /// The server's rows and the loaded page's candidates, one copy per id —
  /// the loaded one, which a redraw or an edit reaches first — newest first.
  /// [fromServer] null means the server had no answer.
  static List<ChatMessage> merge({
    required List<ChatMessage>? fromServer,
    required List<ChatMessage> loaded,
  }) {
    final byId = <String, ChatMessage>{
      for (final message in fromServer ?? const <ChatMessage>[])
        message.id: message,
      for (final message in loaded)
        if (_isCandidate(message)) message.id: message,
    };
    return byId.values.toList()..sort(_newestFirst);
  }

  /// The polls still taking votes at [now], newest first. A locked one is
  /// left out — it has no words to draw yet — and so is one still sending.
  static List<ChatMessage> openPolls(List<ChatMessage> live, DateTime now) => [
    for (final message in live)
      if (message.poll case final poll?
          when !poll.isClosedAt(now) && !message.isLocked && !message.isPending)
        message,
  ]..sort(_newestFirst);

  /// When the next of [polls] closes after [now], for the bar to drop it
  /// then without waiting for anything else to change.
  static DateTime? nextClose(List<ChatMessage> polls, DateTime now) {
    DateTime? soonest;
    for (final message in polls) {
      final closesAt = message.poll?.closesAt;
      if (closesAt == null || !closesAt.isAfter(now)) continue;
      if (soonest == null || closesAt.isBefore(soonest)) soonest = closesAt;
    }
    return soonest;
  }

  static int _newestFirst(ChatMessage a, ChatMessage b) =>
      (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
}
