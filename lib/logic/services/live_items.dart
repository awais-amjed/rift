import '../../data/classes/chat_message.dart';

/// What the bar above a channel's message box holds, decided from rows the
/// chat already has.
///
/// The server's answer (`channel_live_messages`) finds what is live however
/// far back it was posted; the loaded page holds the freshest copy of what it
/// has, and is all there is on a server from before that read.
class LiveItems {
  const LiveItems._();

  /// Could this row belong in the bar? A poll's time is asked later
  /// ([openPolls]): a poll that closed is still a poll.
  static bool _isCandidate(ChatMessage message) =>
      message.poll != null || (message.panel?.live ?? false);

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
    };
    // A row the server named is replaced by the page's copy whatever that
    // copy now says: a panel redrawn without its mark, or a poll ended, is
    // newer than the answer and must not be outvoted by it.
    for (final message in loaded) {
      if (byId.containsKey(message.id) || _isCandidate(message)) {
        byId[message.id] = message;
      }
    }
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

  /// The live panels the bar draws: marked live by their bot, and only while
  /// that bot is connected — a bot that crashed cannot take the mark back, and
  /// a player for one that is not running is a lie. One per bot, its newest:
  /// an older one is left from a session that ended without clearing it.
  /// Nothing until presence has answered, so a panel is never in neither
  /// place: unshown here, it is in the history.
  static List<ChatMessage> shownPanels(
    List<ChatMessage> live, {
    required Set<String> onlineIds,
    required bool onlineKnown,
  }) {
    if (!onlineKnown) return const [];
    final bots = <String>{};
    return [
      // [live] is newest first, so the first seen of each bot is its newest.
      for (final message in live)
        if ((message.panel?.live ?? false) &&
            onlineIds.contains(message.authorId) &&
            bots.add(message.authorId))
          message,
    ];
  }

  /// Of [shown], the panels for this reader. A bot in a call
  /// ([voiceUserIds]) plays to that call, so its panel is only for the people
  /// in it ([callUserIds]); a bot in no call shows to everyone. What is left
  /// out stays out of the history too, since [hideShown] is given all of
  /// [shown].
  static List<ChatMessage> forCall(
    List<ChatMessage> shown, {
    required Set<String> callUserIds,
    required Set<String> voiceUserIds,
  }) => [
    for (final message in shown)
      if (!voiceUserIds.contains(message.authorId) ||
          callUserIds.contains(message.authorId))
        message,
  ];

  /// Of a channel's [rows], the live panels of the bots ([botIds]) in this
  /// device's call ([callUserIds]): a player follows the people in its call
  /// into every channel they read, not only the one it was posted in. Only a
  /// bot's: a server before 024 let a member write blocks onto a plain message
  /// of their own, and one naming the call reached everybody in it.
  static List<ChatMessage> callPanels(
    List<ChatMessage> rows, {
    required Set<String> callUserIds,
    required Set<String> botIds,
  }) => [
    for (final message in rows)
      if ((message.panel?.live ?? false) &&
          callUserIds.contains(message.authorId) &&
          botIds.contains(message.authorId))
        message,
  ];

  /// The bar's panels: [here], the open channel's, and the call's players
  /// from other channels ([fromCall], newest first), still one per bot. A bot
  /// that has one here keeps that one, the copy a redraw reaches first.
  static List<ChatMessage> withCallPanels(
    List<ChatMessage> here,
    List<ChatMessage> fromCall,
  ) {
    final bots = {for (final message in here) message.authorId};
    final added = [
      for (final message in fromCall)
        if (bots.add(message.authorId)) message,
    ];
    if (added.isEmpty) return here;
    return [...here, ...added]..sort(_newestFirst);
  }

  /// [history] without the panels the bar is showing, which are drawn there
  /// instead. The same list when none of them is on it, so the history's
  /// rows are not rebuilt for a bar they have nothing to do with.
  static List<ChatMessage> hideShown(
    List<ChatMessage> history,
    List<ChatMessage> shown,
  ) {
    if (shown.isEmpty) return history;
    final ids = {for (final message in shown) message.id};
    if (!history.any((m) => ids.contains(m.id))) return history;
    return [
      for (final message in history)
        if (!ids.contains(message.id)) message,
    ];
  }

  static int _newestFirst(ChatMessage a, ChatMessage b) =>
      (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
}
