import '../../data/participant_identity.dart';

/// Which tone somebody else starting or stopping watching a stream earns.
enum WatchCue { started, stopped }

/// The tones one remote participant's change of streams earns this client.
///
/// Heard by the stream's sharer and by whoever is already watching it — the
/// people in front of it — and never by the watcher, whose own click is its
/// own feedback. [previous] is null the first time a participant's list is
/// seen: that is where they already were, not something they just did, or
/// joining a call would sound every stream everyone is watching.
///
/// [localIdentity] is this client's voice identity: a desktop share runs on a
/// `_screenshare` connection of its own, a phone's rides the voice one.
List<WatchCue> watchCues({
  required Set<String>? previous,
  required Set<String> current,
  required String? localIdentity,
  required Set<String> watchedHere,
}) {
  if (previous == null) return const [];
  bool concernsMe(String share) =>
      share == localIdentity ||
      ParticipantIdentity.isShareOf(share, localIdentity) ||
      watchedHere.contains(share);
  return [
    for (final share in current.difference(previous))
      if (concernsMe(share)) WatchCue.started,
    for (final share in previous.difference(current))
      if (concernsMe(share)) WatchCue.stopped,
  ];
}
