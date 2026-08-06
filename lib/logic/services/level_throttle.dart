/// Thins a fast stream of audio levels down to a rate a meter can paint,
/// without losing the peaks.
///
/// WebRTC delivers a frame every 10 ms. The noise gate and the speaking
/// indicator want all of them; a widget repainting a hundred times a second
/// does not. Sampling whichever frame happens to land on the tick would drop
/// short, loud sounds — a clap, the start of a word — so the loudest level
/// since the last emission is carried forward and published instead.
class LevelThrottle {
  /// The shortest gap between published levels.
  final Duration interval;

  double _peak = 0;
  DateTime? _lastAt;

  LevelThrottle({this.interval = const Duration(milliseconds: 50)});

  /// Feeds one measured level. Returns the level to publish, or null when it
  /// is not time yet.
  ///
  /// The first call always publishes, so a meter lights up immediately rather
  /// than after a blank interval.
  double? add(double level, DateTime now) {
    if (level > _peak) _peak = level;
    final last = _lastAt;
    if (last != null && now.difference(last) < interval) return null;
    _lastAt = now;
    final published = _peak;
    _peak = 0;
    return published;
  }

  /// Forgets the pending peak and the clock, so the next [add] publishes
  /// immediately. For when capture stops and starts again.
  void reset() {
    _peak = 0;
    _lastAt = null;
  }
}
