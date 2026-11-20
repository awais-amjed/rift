/// How often the call is told about clipping.
///
/// "Has clipping on" is said once per person per call: leaving and joining
/// again, or turning it off and on, would otherwise put the same line up as
/// often as somebody liked. The mark beside their name says the rest.
/// "Clipped" is said at most once a minute per person, applied here on the
/// way in, since a limit the sender honours is one a modified client skips
/// (the soundboard's cooldown works the same way).
///
/// A call here is this client's own stay in a channel: [reset] when it leaves
/// on purpose or moves to another, and not when Rift rejoins by itself.
class ClipNoticeRules {
  static const Duration clipInterval = Duration(minutes: 1);

  final Set<String> _told = {};
  final Map<String, DateTime> _lastClip = {};

  /// Of [userIds] (everyone in the call with clipping on), those not yet
  /// told about in this call, in the order given. They count as told now.
  List<String> newlyClipping(
    Iterable<String> userIds, {
    required String selfId,
  }) => [
    for (final id in userIds)
      if (id != selfId && _told.add(id)) id,
  ];

  /// Whether a clip by [userId] at [now] is told.
  bool admitClip(String userId, DateTime now) {
    final last = _lastClip[userId];
    if (last != null && now.difference(last) < clipInterval) return false;
    _lastClip[userId] = now;
    return true;
  }

  void reset() {
    _told.clear();
    _lastClip.clear();
  }
}

/// The line for [names] having clipping on, one line however many joined
/// at once.
String clippingOnText(List<String> names) {
  switch (names.length) {
    case 0:
      return '';
    case 1:
      return '${names[0]} has clipping on';
    case 2:
      return '${names[0]} and ${names[1]} have clipping on';
    default:
      final rest = names.length - 2;
      final others = rest == 1 ? '1 other' : '$rest others';
      return '${names[0]}, ${names[1]} and $others have clipping on';
  }
}

/// The line for [name] having kept the last [seconds] of the call.
String clippedText(String name, int seconds) {
  final span = switch (seconds) {
    1 => 'second',
    60 => 'minute',
    120 => '2 minutes',
    _ => '$seconds seconds',
  };
  return '$name clipped the last $span';
}
