import 'dart:convert';

/// Instructions the server sends straight to a connected client, over the
/// LiveKit data channel.
///
/// Two, and both say "leave where you are and join again":
///
/// **move** — staff pulling someone from the call they're in into another
/// channel (the `move_user` edge function). It is a signal rather than a
/// server-side relocation because the client is what holds the channel keys;
/// being dragged into a room it never fetched a key for would leave it deaf in
/// a call, with its sidebar still pointing at the old channel. Told to join, it
/// takes the ordinary join path instead.
///
/// **rejoin** — the call itself has moved to another LiveKit (`move_call`).
/// The destination is the channel you are already in, which is why it is not a
/// `move`: nothing about the sidebar changes, only which server is carrying
/// the audio. A room cannot migrate, so everybody reconnecting at once is what
/// moving a call *is*.
///
/// Authenticity is [fromServer]: a packet sent through the LiveKit API arrives
/// with no sender, which no peer in the room can imitate. Anything with a
/// sender is another member talking, and a member cannot move anyone.
class VoiceSignal {
  VoiceSignal._();

  /// Keep in sync with `move_user/index.ts` and `move_call/index.ts` in the
  /// `rift-self-host` repository, which is where the server's endpoints live.
  static const String moveTopic = 'rift.move';
  static const int version = 1;

  /// The channel to join, or null when [data] isn't a move worth obeying.
  ///
  /// Every reason to refuse returns null rather than throwing: this runs on
  /// whatever bytes arrive on a public data channel, and a malformed packet is
  /// an ordinary event, not an error.
  static String? moveDestination({
    required List<int> data,
    required String? topic,
    required bool fromServer,
  }) {
    if (!fromServer || topic != moveTopic) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }

    if (decoded is! Map) return null;
    if (decoded['type'] != 'move') return null;
    // An unknown version is a newer server talking to an older client. Ignoring
    // it is the safe reading: the fields we'd act on may mean something else.
    if (decoded['v'] != version) return null;

    final channelId = decoded['channel_id'];
    if (channelId is! String || channelId.isEmpty) return null;
    return channelId;
  }

  /// Whether this packet says the call has moved to another LiveKit.
  ///
  /// The caller's job is then to drop its cached token — which names the node
  /// the call has just left — and join the same channel again. Same refusals
  /// as [moveDestination], and for the same reason.
  static bool isRejoin({
    required List<int> data,
    required String? topic,
    required bool fromServer,
  }) {
    if (!fromServer || topic != moveTopic) return false;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return false;
    }

    if (decoded is! Map) return false;
    if (decoded['type'] != 'rejoin') return false;
    if (decoded['v'] != version) return false;
    final channelId = decoded['channel_id'];
    return channelId is String && channelId.isNotEmpty;
  }
}
