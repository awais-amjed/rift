import 'dart:convert';

/// The notice a clip becomes: "this person just kept the last N seconds of
/// this call", told to the others so nobody is recorded without hearing so.
///
/// It is sent by the server (`note_clip`), never by the clipper: the clipper's
/// app asks, the server checks that device's connection is in the call, and
/// sends this through LiveKit's API naming that connection's identity. A
/// packet from the API has no sender, which no member can fake — as with a
/// move (`VoiceSignal`). Until console 1.9.0 the clipper sent it on the data
/// channel itself (version 1), which needed the soundboard right, so a member
/// without it clipped unannounced; those packets are not believed any more.
///
/// It carries no audio and nothing about what was kept, only how much. The
/// `clipping` attribute (`VoiceAttributes.clippingKey`) and its mark are what
/// tell the call that someone could clip; this is the "just did".
abstract final class ClipSignal {
  static const String topic = 'rift.clip';

  /// The server's form (`note_clip`). Version 1 was a member's own packet.
  static const int version = 2;

  /// The longest a clip can be: the longest ring a client keeps.
  static const int maxSeconds = 120;

  /// Who clipped (their voice connection's identity) and how many seconds,
  /// or null when [data] is not a notice to believe.
  ///
  /// Null rather than a throw for every refusal. The length is held to
  /// 1..[maxSeconds], so a number cannot word a notice beyond what a client
  /// keeps.
  static ({String identity, int seconds})? read({
    required List<int> data,
    required String? topic,
    required bool fromServer,
  }) {
    if (!fromServer || topic != ClipSignal.topic) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != version || decoded['type'] != 'clipped') return null;
    final identity = decoded['identity'];
    final seconds = decoded['seconds'];
    if (identity is! String || identity.isEmpty || seconds is! int) {
      return null;
    }
    return (identity: identity, seconds: seconds.clamp(1, maxSeconds));
  }
}
