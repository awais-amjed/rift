import '../../data/participant_identity.dart';

/// Who in a call currently has something shared.
///
/// A share is not on the sharer's own connection — it is a second one, with a
/// `_screenshare` or `_soundshare` identity (except a phone's screen share,
/// which rides the connection it already has). So "is this person sharing?"
/// cannot be answered from their own participant, and their roster row would
/// otherwise be the one place in the app that cannot say what they are doing.
class SharePresence {
  /// User ids, never identities: it is the *person* whose row shows the icon,
  /// and a share made from another of their devices is still theirs.
  final Set<String> screenSharers;
  final Set<String> soundSharers;

  const SharePresence({
    required this.screenSharers,
    required this.soundSharers,
  });

  static const empty = SharePresence(screenSharers: {}, soundSharers: {});

  bool sharesScreen(String userId) => screenSharers.contains(userId);

  bool sharesSound(String userId) => soundSharers.contains(userId);
}

/// Reads [participants] for shares. Generic over the participant type so the
/// rule can be tested without a live LiveKit room, like `voiceTilesFor`.
SharePresence sharePresenceOf<T>(
  Iterable<T> participants, {
  required String Function(T) identityOf,
  required bool Function(T) publishesScreenshare,
}) {
  final screens = <String>{};
  final sounds = <String>{};
  for (final participant in participants) {
    final identity = identityOf(participant);
    final userId = ParticipantIdentity.userIdOf(identity);
    if (ParticipantIdentity.isScreenshare(identity)) {
      screens.add(userId);
    } else if (ParticipantIdentity.isSoundShare(identity)) {
      sounds.add(userId);
    } else if (publishesScreenshare(participant)) {
      // A phone publishes its screen on the connection it already has, so
      // there is no second identity to find it by.
      screens.add(userId);
    }
  }
  return SharePresence(screenSharers: screens, soundSharers: sounds);
}
