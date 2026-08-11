/// Who is in which voice channel, and the wire format members tell each other
/// with.
///
/// Split out from presence on purpose. Presence answers *who is online* — a
/// fact that changes once per session and is worth the rationed event it costs
/// (Realtime allows one client five presence publishes per 30 seconds and kills
/// the channel on the sixth). *Where* someone is changes far too often for that
/// budget: people hop voice channels constantly. So location travels as a plain
/// broadcast, which has no per-client window, and presence is left to do the
/// one thing broadcast cannot — vanish on its own when a client dies.
///
/// That pairing is what [rosters] encodes: a location is only believed while
/// presence still vouches for the person it belongs to. A client that crashes
/// mid-call never gets to say it left, and doesn't need to.
///
/// Pure, so the merge rules can be tested without a socket. [VoiceBroadcast]
/// holds the socket and obeys them.
class VoiceLocations {
  VoiceLocations._();

  /// Broadcast topic and event. Keep in sync with nothing else — both ends of
  /// this conversation are Rift clients.
  static String topic(String serverId) => 'voice:$serverId';
  static const String event = 'here';
  static const int version = 1;

  static Map<String, dynamic> encode({
    required String userId,
    required String? channelId,
  }) => {'v': version, 'userId': userId, 'channelId': channelId};

  /// The delta in a broadcast [message], or null if it isn't one we understand.
  ///
  /// Realtime wraps what was sent in a `payload` key, and older brokers hand it
  /// over flat, so both shapes are accepted — the same unwrap the chat topics do.
  ///
  /// A null `channelId` is a real value — it means *left voice* — so "absent"
  /// and "null" have to stay distinguishable, hence the record rather than a
  /// bare string.
  static ({String userId, String? channelId})? decode(
    Map<String, dynamic> message,
  ) {
    final payload = (message['payload'] ?? message) as Map<String, dynamic>?;
    if (payload == null) return null;
    if (payload['v'] != version) return null;
    final userId = payload['userId'];
    if (userId is! String || userId.isEmpty) return null;
    final channelId = payload['channelId'];
    if (channelId != null && (channelId is! String || channelId.isEmpty)) {
      return null;
    }
    return (userId: userId, channelId: channelId as String?);
  }

  /// [current] with [userId] moved to [channelId], or dropped when it's null.
  static Map<String, String> applyDelta(
    Map<String, String> current, {
    required String userId,
    required String? channelId,
  }) {
    final next = Map<String, String>.of(current);
    if (channelId == null) {
      next.remove(userId);
    } else {
      next[userId] = channelId;
    }
    return next;
  }

  /// Folds a freshly fetched [snapshot] into what we already have.
  ///
  /// [heard] is everyone whose own broadcast reached us while the snapshot was
  /// in flight. They win: the snapshot was taken before they spoke, and
  /// applying it wholesale would drag them back to where they used to be. For
  /// everyone else the snapshot is the better answer — it came from LiveKit,
  /// which is the only participant that can't be out of date.
  static Map<String, String> mergeSnapshot(
    Map<String, String> snapshot, {
    required Map<String, String> current,
    required Set<String> heard,
  }) {
    final next = Map<String, String>.of(snapshot);
    for (final userId in heard) {
      final live = current[userId];
      if (live == null) {
        next.remove(userId);
      } else {
        next[userId] = live;
      }
    }
    return next;
  }

  /// The per-channel rosters to draw, as user ids.
  ///
  /// Two filters, both load-bearing. Anyone presence doesn't list as [online]
  /// is dropped — that's how a client that died without saying goodbye leaves
  /// the channel list. And [excluding] takes out the local user, whose own
  /// channel is drawn from live LiveKit participants instead; without it we'd
  /// be listed twice in the call we're actually in.
  static Map<String, List<String>> rosters({
    required Map<String, String> locations,
    required Set<String> online,
    String? excluding,
  }) {
    final result = <String, List<String>>{};
    for (final entry in locations.entries) {
      if (entry.key == excluding || !online.contains(entry.key)) continue;
      result.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    for (final ids in result.values) {
      ids.sort();
    }
    return result;
  }
}
