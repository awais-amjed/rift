import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'host_platform.dart';

/// Picture-in-picture: the floating window a call shrinks into when the app is
/// put away.
///
/// The native half is in `MainActivity.kt`, and the split is deliberate. The
/// *moment* the window shrinks belongs to Android — a home gesture, a recents
/// swipe — and cannot be predicted from Dart. What Dart knows is whether the
/// call is worth floating at all, which is what [setArmed] says. Everything
/// else arrives as a push through [isInPip]; nothing here polls.
///
/// A no-op off Android, where the platform has no equivalent.
class PipService {
  PipService._();

  static final PipService instance = PipService._();

  static const MethodChannel _channel = MethodChannel('rift/pip');

  /// Whether the app is currently *in* the floating window, so the UI can
  /// become the one thing worth seeing at that size.
  ///
  /// A notifier rather than a stream: this is a single piece of current state
  /// that widgets rebuild against, and a late listener should get the answer
  /// rather than wait for it to change again.
  final ValueNotifier<bool> isInPip = ValueNotifier(false);

  bool _listening = false;
  bool _armed = false;
  bool? _available;

  /// Whether the device offers PiP at all. Manufacturers and device admins can
  /// both take it away, so a new enough Android is not on its own an answer.
  Future<bool> get isAvailable async {
    if (!HostPlatform.isMobile) return false;
    try {
      return _available ??=
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
      debugPrint('PipService: could not ask about availability – $e');
      return false;
    }
  }

  /// Says whether the call currently has something worth floating.
  ///
  /// Armed is not the same as entered: this tells Android to shrink the window
  /// *if* the user leaves, which is why it is safe to leave on for the length
  /// of a call and wrong to leave on after one.
  Future<void> setArmed(bool armed) async {
    if (!HostPlatform.isMobile || _armed == armed) return;
    if (armed && !await isAvailable) return;
    _armed = armed;
    _ensureListening();
    try {
      await _channel.invokeMethod('setAutoEnter', {'enabled': armed});
    } catch (e) {
      _armed = !armed;
      debugPrint('PipService: could not arm – $e');
    }
  }

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        isInPip.value = call.arguments == true;
      }
      return null;
    });
  }
}
