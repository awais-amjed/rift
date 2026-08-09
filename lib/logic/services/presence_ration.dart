/// The arithmetic behind staying visible in Supabase Realtime Presence.
///
/// Realtime allows one client **5 presence events per 30 seconds**
/// (`CLIENT_PRESENCE_MAX_CALLS` / `CLIENT_PRESENCE_WINDOW_MS`, realtime v2.102
/// defaults; the tenant columns `max_client_presence_events_per_window` and
/// `client_presence_window_ms` override them). The sixth is not refused — it
/// logs `ClientPresenceRateLimitReached` and **terminates the channel**, which
/// takes the client's presence entry with it and leaves every later track
/// timing out against a process that no longer exists.
///
/// Pure so the rules can be tested without a socket; [ChannelPresenceCubit]
/// holds the socket and obeys them.
class PresenceRation {
  PresenceRation._();

  /// The server's window, and what we allow ourselves inside it. One event
  /// short of the limit on purpose: the reserve covers the track that follows
  /// a rebuild, which lands on a fresh connection but can't afford to be wrong.
  static const Duration window = Duration(seconds: 30);
  static const int maxPerWindow = 4;

  /// First wait before rebuilding a channel that can't publish, doubling per
  /// attempt up to [maxRebuildDelay]. A rebuild opens a new socket, so this is
  /// also what stops a broken server becoming a reconnect storm.
  static const Duration rebuildBaseDelay = Duration(seconds: 2);
  static const Duration maxRebuildDelay = Duration(seconds: 30);

  /// How long to hold an update back so we stay inside the ration.
  ///
  /// [recent] is when the earlier updates went out, in any order. Zero while
  /// there is room in the window; otherwise long enough for the oldest to fall
  /// out of it, plus a second, because the server's clock is not ours.
  static Duration publishWait({
    required List<DateTime> recent,
    required DateTime now,
  }) {
    final inWindow = [
      for (final at in recent)
        if (now.difference(at) < window) at,
    ];
    if (inWindow.length < maxPerWindow) return Duration.zero;

    final oldest = inWindow.reduce((a, b) => a.isBefore(b) ? a : b);
    return window - now.difference(oldest) + const Duration(seconds: 1);
  }

  /// [recent] with everything older than the window dropped, plus [now].
  static List<DateTime> spend(List<DateTime> recent, DateTime now) => [
    for (final at in recent)
      if (now.difference(at) < window) at,
    now,
  ];

  /// Backoff before the [attempt]-th rebuild, counting from zero.
  static Duration rebuildDelay(int attempt) {
    final delay = rebuildBaseDelay * (1 << attempt.clamp(0, 8));
    return delay > maxRebuildDelay ? maxRebuildDelay : delay;
  }

  /// Whether our own entry has gone missing from what the server is telling
  /// everyone, while we still think we published one.
  ///
  /// A weaker signal than it looks: when Realtime ends a channel it leaves that
  /// client's *own* copy of the state intact, so this stays quiet for the case
  /// it would be most useful for. It still catches an entry lost some other
  /// way, and costs one update to answer.
  static bool shouldRetrack({
    required bool tracked,
    required String? localUserId,
    required Set<String> onlineUserIds,
  }) => tracked && localUserId != null && !onlineUserIds.contains(localUserId);
}
