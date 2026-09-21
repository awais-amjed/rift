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
  Timer? _pending;

  bool get isDown => _down;

  /// A press, stamped in the desktop's milliseconds.
  void press(int timestamp) {
    _lastPressAt = timestamp;
    _pending?.cancel();
    _pending = null;
    if (_down) return;
    _down = true;
    onChanged(true);
  }

  /// A release, stamped in the desktop's milliseconds.
  void release(int timestamp) {
    if (!_down) return;
    final pressedAt = _lastPressAt;
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
  void reset() => _settle();

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
