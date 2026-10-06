import '../../data/classes/participant_info.dart';
import '../../data/participant_identity.dart';

/// Collapses the LiveKit roster into one row per person.
class ParticipantRoster {
  const ParticipantRoster._();

  /// A user present from several devices appears once — and once more for
  /// each kind of share they have running, which is a connection of theirs
  /// rather than another of them. The surviving entry prefers the local
  /// participant, then a speaking one, then a mic-enabled one, so the row
  /// reflects the device they are actually talking from.
  ///
  /// What the person watches is the union over their devices: a stream open
  /// on their laptop still has them in front of it when their phone wins
  /// the row.
  static List<ParticipantInfo> dedupeByUser(List<ParticipantInfo> infos) {
    final byKey = <String, ParticipantInfo>{};
    final watching = <String, Set<String>>{};
    for (final info in infos) {
      final key = '${info.userId}|${_kind(info)}';
      (watching[key] ??= {}).addAll(info.watching);
      final existing = byKey[key];
      if (existing == null || _rank(info) > _rank(existing)) {
        byKey[key] = info;
      }
    }
    return [
      for (final MapEntry(:key, value: info) in byKey.entries)
        info.watching.length == watching[key]!.length
            ? info
            : info.withWatching(watching[key]!),
    ];
  }

  /// The people watching the stream with [shareIdentity], in roster order.
  ///
  /// Never the sharer: opening the preview of your own screen is not an
  /// audience, and the same rule keeps the sharer's tones quiet
  /// (`watchCues`).
  static List<ParticipantInfo> watchersOf(
    List<ParticipantInfo> roster,
    String shareIdentity,
  ) {
    final owner = ParticipantIdentity.userIdOf(shareIdentity);
    return [
      for (final info in roster)
        if (!info.isShare &&
            info.userId != owner &&
            info.watching.contains(shareIdentity))
          info,
    ];
  }

  /// Whether the participant with [identity] is speaking, according to the
  /// roster the LiveKit cubit publishes.
  ///
  /// That roster is the only place the two speech signals are merged: your own
  /// mic level, measured locally, and everyone else's from the server's
  /// active-speaker detection. Reading LiveKit's own `isSpeaking` instead gets
  /// the local user wrong — the server never reports you promptly, so your tile
  /// stays dark while your avatar in the sidebar glows.
  ///
  /// [fallback] answers for an identity the roster doesn't carry: the frames
  /// before the first sync, and the losing device of a multi-device user.
  static bool isSpeaking(
    List<ParticipantInfo> roster,
    String identity, {
    bool fallback = false,
  }) {
    for (final info in roster) {
      if (info.identity == identity) return info.isSpeaking;
    }
    return fallback;
  }

  /// Whether the participant with [identity] has their ears closed, by their
  /// own choice or a moderator's. The tile reads it here so that it and the
  /// sidebar row ([voiceStatusIcons]) agree on what somebody is doing.
  static bool isDeafened(List<ParticipantInfo> roster, String identity) {
    for (final info in roster) {
      if (info.identity == identity) {
        return info.isDeafened || info.isServerDeafened;
      }
    }
    return false;
  }

  /// Whether the screen share with [identity] says its window is minimised.
  static bool isSharePaused(List<ParticipantInfo> roster, String identity) {
    for (final info in roster) {
      if (info.identity == identity) return info.isSharePaused;
    }
    return false;
  }

  /// What the screen share with [identity] says it is sending, as a label.
  static String? shareQuality(List<ParticipantInfo> roster, String identity) {
    for (final info in roster) {
      if (info.identity == identity) return info.shareQuality;
    }
    return null;
  }

  /// Which of a user's connections this is: themselves, their screen, or
  /// their sound. Two of them must not collapse into one row.
  static int _kind(ParticipantInfo p) {
    if (p.isScreenshare) return 1;
    if (p.isSoundShare) return 2;
    return 0;
  }

  static int _rank(ParticipantInfo p) =>
      (p.isLocal ? 4 : 0) +
      (p.isSpeaking ? 2 : 0) +
      (p.isMicrophoneEnabled ? 1 : 0);
}
