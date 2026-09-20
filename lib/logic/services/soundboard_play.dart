import 'dart:convert';

/// The packet one person's press becomes, and the rules a listener applies to
/// it before anything comes out of their speakers.
///
/// A play is sent on the call's own LiveKit data channel rather than published
/// as a track or written to the database. Three things follow from that, and
/// they are the whole design:
///
///   * **the audience is exactly the call.** The room is the delivery list, so
///     there is no topic to police and nobody outside can hear it;
///   * **every listener plays it themselves**, out of their own copy of the
///     clip, at their own volume. "Turn his soundboard down" is then a real
///     control rather than a request to the person pressing the button;
///   * **the listener enforces the limits.** A cooldown a *sender* honours is
///     a cooldown a modified client removes. Both of the ones here are
///     applied on the way in, so the person being spammed is the one who
///     decides — which is the only place the decision works.
///
/// Unlike [VoiceSignal], a packet with no sender is dropped rather than
/// trusted: this is exactly the case where we need to know whose it was, both
/// to rate-limit them and to honour a mute set against them.
class SoundboardPlay {
  const SoundboardPlay._();

  static const String topic = 'rift.sound';
  static const int version = 1;

  /// The shortest gap between two clips from the same person a listener will
  /// honour. Long enough that a held-down button is one sound, short enough
  /// that two people answering each other still works.
  static const Duration cooldown = Duration(milliseconds: 1200);

  /// However long a clip claims to be, playback is cut off here.
  ///
  /// This is the real bound on a long clip. `duration_ms` on the row is the
  /// uploader's word for it and the 512 KB size limit is generous at a low
  /// bitrate, so the only number that can actually stop a five-minute track
  /// is one the listener applies.
  static const Duration maxPlayback = Duration(seconds: 8);

  static List<int> encode(String soundId) =>
      utf8.encode(jsonEncode({'v': version, 'type': 'sound', 'id': soundId}));

  /// The clip being asked for, or null when [data] is not a play worth
  /// obeying.
  ///
  /// Every refusal is a null rather than a throw: this runs on whatever bytes
  /// arrive on a channel any participant can write to, so a malformed packet
  /// is an ordinary event and not an error.
  static String? soundId({
    required List<int> data,
    required String? topic,
    required bool fromParticipant,
  }) {
    if (!fromParticipant || topic != SoundboardPlay.topic) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }

    if (decoded is! Map) return null;
    if (decoded['type'] != 'sound') return null;
    // An unknown version is a newer client talking to an older one. Ignoring
    // it is the safe reading: the fields we would act on may mean something
    // else by then.
    if (decoded['v'] != version) return null;

    final id = decoded['id'];
    if (id is! String || id.isEmpty) return null;
    return id;
  }
}

/// Who is allowed to be heard, and how often.
///
/// Kept apart from the player so the rule can be tested without an audio
/// stack: it is a map of last-heard times and one comparison, and it is the
/// only thing standing between a room and somebody holding a button down.
class SoundboardGate {
  final Map<String, DateTime> _lastHeard = {};

  /// Whether a play from [userId] at [now] should be heard, recording it if
  /// so. A press inside the cooldown is dropped and does **not** push the
  /// window out — otherwise holding the button down would keep the gate shut
  /// forever rather than letting one through every [SoundboardPlay.cooldown].
  bool admit(String userId, DateTime now) {
    final last = _lastHeard[userId];
    if (last != null && now.difference(last) < SoundboardPlay.cooldown) {
      return false;
    }
    _lastHeard[userId] = now;
    return true;
  }

  /// Forget everybody — the call ended, so the next one starts clean.
  void clear() => _lastHeard.clear();
}
