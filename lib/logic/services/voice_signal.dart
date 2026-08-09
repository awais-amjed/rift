import 'dart:convert';

/// Instructions the server sends straight to a connected client, over the
/// LiveKit data channel.
///
/// Only one so far: **move** — staff pulling someone from the call they're in
/// into another channel (the `move_user` edge function). It is a signal rather
/// than a server-side relocation because the client is what holds the channel
/// keys; being dragged into a room it never fetched a key for would leave it
/// deaf in a call, with its sidebar still pointing at the old channel. Told to
/// join, it takes the ordinary join path instead.
///
/// Authenticity is [fromServer]: a packet sent through the LiveKit API arrives
/// with no sender, which no peer in the room can imitate. Anything with a
/// sender is another member talking, and a member cannot move anyone.
class VoiceSignal {
  VoiceSignal._();

  /// Keep in sync with `edge_functions/supabase/functions/move_user/index.ts`.
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
}
