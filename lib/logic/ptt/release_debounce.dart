import 'dart:async';

/// Turns a desktop's push-to-talk key events into one press and one release
/// per hold.
///
/// GNOME's global-shortcuts portal reports a held key two different ways, and
/// the same hold can switch between them. Sometimes every auto-repeat arrives
/// as a fresh press, and only letting go sends a release. Sometimes every
/// repeat arrives as a press *and* a release stamped the same millisecond, so
/// a held key looks like a burst of taps 30ms apart — and the real release is
/// just the last of those pairs, with nothing to tell it apart except that no
/// press follows.
///
/// So a release stamped within [_sameInstant] of the press before it is only
/// believed once [window] passes with no press after it. A release with its
/// own timestamp is a real key-up and goes through at once, which keeps the
/// common case free of any added delay.
///
/// Presses and releases arrive on two separate signal streams, and a backlog
/// of both is not delivered in the order it happened. A window that has sat
/// covered can leave Rift's thread waiting about a second per frame, and
/// then a hold's queued repeat presses land *after* its release. Taken as
/// they come, the last of them reopened the mic with no release left to close
/// it — for over three minutes in one test, across several more holds. So an
/// edge stamped before the latest edge of the other kind is stale and is
/// dropped.
class ReleaseDebounce {
  /// How long a same-instant release waits for the next repeat. Comfortably
  /// over GNOME's default 30ms repeat interval, and short enough to vanish
  /// inside the 200ms the mic stays open after release anyway.
  static const Duration defaultWindow = Duration(milliseconds: 100);

  /// A repeat's press and release have been seen 0 and 1ms apart; a finger
  /// is never that quick.
  static const int _sameInstant = 1;

  final Duration window;
  final void Function(bool pressed) onChanged;

  ReleaseDebounce({required this.onChanged, this.window = defaultWindow});

  bool _down = false;
  int? _lastPressAt;
  int? _lastReleaseAt;
  Timer? _pending;

  bool get isDown => _down;

  /// A press, stamped in the desktop's milliseconds.
  void press(int timestamp) {
    // At the same instant counts as stale: a repeat's press and release share
    // a millisecond, and its release has already been seen.
    final releasedAt = _lastReleaseAt;
    if (releasedAt != null && timestamp <= releasedAt) return;
    _lastPressAt = timestamp;
    _pending?.cancel();
    _pending = null;
    if (_down) return;
    _down = true;
    onChanged(true);
  }

  /// A release, stamped in the desktop's milliseconds.
  void release(int timestamp) {
    final pressedAt = _lastPressAt;
    if (pressedAt != null && timestamp < pressedAt) return;
    _lastReleaseAt = timestamp;
    if (!_down) return;
    final pairedWithPress =
        pressedAt != null && (timestamp - pressedAt).abs() <= _sameInstant;
    if (!pairedWithPress) {
      _settle();
      return;
    }
    _pending?.cancel();
    _pending = Timer(window, _settle);
  }

  /// Lets go without waiting, for when the source itself goes away.
  void reset() {
    _lastPressAt = null;
    _lastReleaseAt = null;
    _settle();
  }

  void dispose() {
    _pending?.cancel();
    _pending = null;
  }

  void _settle() {
    _pending?.cancel();
    _pending = null;
    if (!_down) return;
    _down = false;
    onChanged(false);
  }
}
