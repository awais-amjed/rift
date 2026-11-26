/// Our own reactions whose ring has not come back yet.
///
/// `toggle_reaction` answers a message's counts as they stand after the
/// change, and the change rings the conversation like anybody's. That ring
/// asks for the same counts again, so a tap cost two reads where one was
/// already in hand. A ring names who reacted (self-host 067); one naming us,
/// about a message we just toggled, is the echo and is let go.
///
/// Counted per message, one per toggle: each changes one row and rings once.
/// A ring naming us with nothing owed is another of our devices, and is read.
/// A ring can be lost, so what is owed lapses after [within], or a later one
/// from another device would be let go in its place.
class ReactionEchoes {
  ReactionEchoes({
    this.within = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration within;

  /// The time, which a test sets.
  final DateTime Function() _now;

  /// When each toggle not yet echoed was answered, by message.
  final Map<String, List<DateTime>> _owed = {};

  /// A toggle of ours on [messageId] was answered with its counts.
  void expect(String messageId) =>
      _owed.putIfAbsent(messageId, () => []).add(_now());

  /// Whether a ring from us about [messageId] is the echo of a toggle whose
  /// counts are already held; if so it is crossed off.
  bool take(String messageId) {
    final now = _now();
    _owed.removeWhere((_, at) {
      at.removeWhere((t) => now.difference(t) >= within);
      return at.isEmpty;
    });
    final owed = _owed[messageId];
    if (owed == null) return false;
    owed.removeAt(0);
    if (owed.isEmpty) _owed.remove(messageId);
    return true;
  }
}
