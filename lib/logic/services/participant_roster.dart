import '../../data/classes/participant_info.dart';

/// Collapses the LiveKit roster into one row per person.
class ParticipantRoster {
  const ParticipantRoster._();

  /// A user present from several devices appears once (and once more for their
  /// screenshare). The surviving entry prefers the local participant, then a
  /// speaking one, then a mic-enabled one — so the row reflects the device
  /// they are actually talking from.
  static List<ParticipantInfo> dedupeByUser(List<ParticipantInfo> infos) {
    final byKey = <String, ParticipantInfo>{};
    for (final info in infos) {
      final key = '${info.userId}|${info.isScreenshare}';
      final existing = byKey[key];
      if (existing == null || _rank(info) > _rank(existing)) {
        byKey[key] = info;
      }
    }
    return byKey.values.toList();
  }

  static int _rank(ParticipantInfo p) =>
      (p.isLocal ? 4 : 0) +
      (p.isSpeaking ? 2 : 0) +
      (p.isMicrophoneEnabled ? 1 : 0);
}
