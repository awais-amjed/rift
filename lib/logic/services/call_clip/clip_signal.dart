import 'dart:convert';

/// The packet a clip becomes: "I just kept the last N seconds of this call",
/// sent to the call on its data channel the way a soundboard press is
/// (`SoundboardPlay`).
///
/// It carries no audio and nothing about what was kept, only how much, so
/// the others can be told. A modified client can leave it out; the
/// `clipping` attribute (`VoiceAttributes.clippingKey`) and its mark are
/// what tell the call that someone could, and this is a courtesy on top.
abstract final class ClipSignal {
  static const String topic = 'rift.clip';

  /// Bumped when the fields change meaning; an older client ignores it.
  static const int version = 1;

  /// The longest a clip can be: the longest ring a client keeps.
  static const int maxSeconds = 120;

  static List<int> encode({required int seconds}) => utf8.encode(
    jsonEncode({'v': version, 'type': 'clipped', 'seconds': seconds}),
  );

  /// How many seconds [data] says were clipped, or null when it is not a
  /// clip worth telling anybody about.
  ///
  /// Null rather than a throw for every refusal: any participant can write
  /// to the channel, so a malformed packet is an ordinary event. The length
  /// is held to 1..[maxSeconds], so a hostile number cannot word a notice.
  static int? secondsOf({
    required List<int> data,
    required String? topic,
    required bool fromParticipant,
  }) {
    if (!fromParticipant || topic != ClipSignal.topic) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != version || decoded['type'] != 'clipped') return null;
    final seconds = decoded['seconds'];
    if (seconds is! int) return null;
    return seconds.clamp(1, maxSeconds);
  }
}
