/// The streams this client was watching when they dropped out of the call
/// without anybody choosing to stop: the sharer's connection went down and
/// came back, or the call moved to another region and everybody rejoined.
///
/// A stream that disappears is otherwise forgotten at once, so the next
/// stream from the same person does not open already watched. That is right
/// when they stopped sharing, and wrong when their share is back a few
/// seconds later, still the same stream: the viewer had to press Watch again.
/// So for a short while after a drop, the stream is remembered here, and
/// watched again if it comes back.
class WatchResume {
  /// How long a dropped stream is waited for. Long enough for a rejoin — a
  /// fresh token, the key, a connect — and short enough that a stream
  /// started again much later is a new decision for the viewer.
  static const Duration grace = Duration(seconds: 30);

  final Map<String, DateTime> _droppedAt = {};

  /// Remembers [identities] as having dropped out at [now].
  void remember(Iterable<String> identities, DateTime now) {
    for (final identity in identities) {
      _droppedAt[identity] = now;
    }
  }

  /// Whether [identity]'s stream, arriving at [now], is one being waited
  /// for. Answers once: the stream is watched again from here on, and the
  /// next time it drops it is remembered afresh.
  bool take(String identity, DateTime now) {
    final droppedAt = _droppedAt.remove(identity);
    return droppedAt != null && now.difference(droppedAt) <= grace;
  }

  /// Forgets everything — leaving the call, where nothing is coming back.
  void clear() => _droppedAt.clear();
}
