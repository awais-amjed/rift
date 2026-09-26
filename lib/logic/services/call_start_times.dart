/// When each occupied voice channel's call began, for the sidebar's timer.
///
/// Two sources, and neither is enough alone. The server knows when LiveKit
/// created each room, but is only asked when presence connects. Presence says
/// the moment a channel fills, but nothing about calls that began before the
/// app opened. So a start is the server's where it has one, and otherwise the
/// moment this client first saw the channel occupied.
///
/// A server time is forgotten once its channel is seen empty. LiveKit keeps
/// an empty room for a few minutes, so without that a call started again
/// soon after would inherit the last one's start.
class CallStartTimes {
  /// What the sidebar reads: channelId → start, for occupied channels only.
  final Map<String, DateTime> started;

  /// Starts from the last roster, not yet overruled by an empty channel.
  final Map<String, DateTime> fromServer;

  const CallStartTimes({this.started = const {}, this.fromServer = const {}});

  /// A roster answered. Its starts win for channels occupied now, and wait for
  /// the rest until presence shows them occupied.
  CallStartTimes withServer(Map<String, DateTime> server, DateTime now) =>
      CallStartTimes(
        started: const {},
        fromServer: {...fromServer, ...server},
      ).update(started.keys.toSet(), now);

  /// Presence changed: [occupied] is every channel with somebody in it.
  CallStartTimes update(Set<String> occupied, DateTime now) {
    final server = {
      for (final entry in fromServer.entries)
        // Seen occupied before and not now: that call is over.
        if (occupied.contains(entry.key) || !started.containsKey(entry.key))
          entry.key: entry.value,
    };
    return CallStartTimes(
      started: {
        for (final id in occupied) id: server[id] ?? started[id] ?? now,
      },
      fromServer: server,
    );
  }
}
