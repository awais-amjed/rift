import 'dart:async';

/// Answers a doorbell at most once every [atMostEvery], however often it
/// rings.
///
/// A ring on a server's topic is a nudge to go and read again, and any member
/// may send one (`app.can_use_topic`), so a member looping `changed` or
/// `sweep` had every app on the server re-reading as fast as Realtime would
/// carry the rings (security re-review, Nov 26). Each ring here is answered
/// once [settle] has passed, so a burst from one change is one read; rings
/// while that answer is pending join it, and rings in the gap after an answer
/// are answered once, when it ends. Nothing a ring announces is lost: the
/// read after the gap sees it. Unlike a debounce that restarts on every ring,
/// a flood cannot hold the answer off either.
class RingThrottle {
  final Duration settle;
  final Duration atMostEvery;
  final void Function() _answer;

  Timer? _pending;
  Timer? _gap;
  bool _rungInGap = false;

  RingThrottle(
    this._answer, {
    this.settle = const Duration(milliseconds: 250),
    this.atMostEvery = const Duration(seconds: 2),
  });

  void ring() {
    if (_pending != null) return;
    if (_gap != null) {
      _rungInGap = true;
      return;
    }
    _pending = Timer(settle, _fire);
  }

  void _fire() {
    _pending = null;
    _gap = Timer(atMostEvery, () {
      _gap = null;
      if (_rungInGap) {
        _rungInGap = false;
        _fire();
      }
    });
    _answer();
  }

  /// Drops a pending answer, for when what it would read is gone.
  void cancel() {
    _pending?.cancel();
    _pending = null;
    _gap?.cancel();
    _gap = null;
    _rungInGap = false;
  }
}
