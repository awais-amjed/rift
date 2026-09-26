/// When each occupied voice channel's call began, for the sidebar's timer.
///
/// Two sources, and neither is enough alone. The server knows when LiveKit
/// created each room, but is only asked when presence connects. Presence says
/// the moment a channel fills, but nothing about calls that began before the
/// app opened. So a start is the server's where it has one, and otherwise the
/// moment this client first saw the channel occupied.
///
/// A server time is forgotten once its channel is seen empty, and if
/// presence doesn't show the channel occupied within [grace] of the roster
/// answering. The roster can list a session that has already died — an app
/// killed mid-call stays in LiveKit's room for a few seconds — and a start
/// left waiting for that channel would be handed to the next, unrelated call
/// there, minutes later.
class CallStartTimes {
  /// How long a roster's start waits for presence to agree the channel is
  /// occupied: presence connects a moment after the roster is asked for.
  static const grace = Duration(seconds: 15);

  /// What the sidebar reads: channelId → start, for occupied channels only.
  final Map<String, DateTime> started;

  /// Starts from the last roster, not yet overruled by an empty channel.
  final Map<String, DateTime> fromServer;

  /// When the roster behind [fromServer] answered.
  final DateTime? serverAt;

  const CallStartTimes({
    this.started = const {},
    this.fromServer = const {},
    this.serverAt,
  });

  /// A roster answered. Its starts win for channels occupied now, and wait
  /// [grace] for the rest to show up occupied.
  CallStartTimes withServer(Map<String, DateTime> server, DateTime now) =>
      CallStartTimes(
        started: const {},
        fromServer: {...fromServer, ...server},
        serverAt: now,
      ).update(started.keys.toSet(), now);

  /// Presence changed: [occupied] is every channel with somebody in it.
  CallStartTimes update(Set<String> occupied, DateTime now) {
    final waited = serverAt == null || now.difference(serverAt!) > grace;
    final server = {
      for (final entry in fromServer.entries)
        // Occupied: in use. Seen occupied before and not now: that call is
        // over. Never seen occupied: waits out the grace, then goes.
        if (occupied.contains(entry.key) ||
            (!started.containsKey(entry.key) && !waited))
          entry.key: entry.value,
    };
    return CallStartTimes(
      started: {
        for (final id in occupied) id: server[id] ?? started[id] ?? now,
      },
      fromServer: server,
      serverAt: serverAt,
    );
  }
}
