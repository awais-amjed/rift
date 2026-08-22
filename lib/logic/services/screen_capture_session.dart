import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'host_platform.dart';

/// What Android needs in place before a screen can be captured, and what has
/// to be taken down again afterwards.
///
/// Two things, and both are the platform's rules rather than ours:
///
/// 1. **Consent.** MediaProjection shows a system dialog naming the app and
///    warning what it will be able to see. It is not ours to skin or skip, and
///    the answer is per-session.
/// 2. **A foreground service** that declares the `mediaProjection` type. From
///    Android 14 a capture started without one is refused outright, and before
///    that it was merely killed the moment the app lost focus — which is every
///    screen share, since the point is to go and show something else. Neither
///    flutter_webrtc nor the LiveKit SDK ships such a service, so it comes from
///    flutter_background, the same one LiveKit's own Flutter example uses.
///
/// Everywhere else this is all no-ops: the desktop has its own capture
/// pipeline, and a browser asks for consent itself.
class ScreenCaptureSession {
  const ScreenCaptureSession._();

  /// Asks for everything Android wants, and reports whether it was given.
  ///
  /// False means the user declined the system dialog or the service could not
  /// start. Not an error to report: declining is a normal answer, and the
  /// system dialog has already said what was being asked.
  static Future<bool> prepare() async {
    if (!HostPlatform.isMobile) return true;

    try {
      if (!await Helper.requestCapturePermission()) return false;

      // The notification is not decoration — a foreground service must show
      // one, and Android puts a recording indicator beside it. It is also the
      // only reminder, once the app is in the background, that a screen is
      // still going out.
      const config = FlutterBackgroundAndroidConfig(
        notificationTitle: 'Rift is sharing your screen',
        notificationText: 'Your screen is visible to everyone in the call.',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: AndroidResource(
          name: 'ic_launcher',
          defType: 'mipmap',
        ),
        // The package asks for a battery-optimisation exemption by default,
        // which puts a "Let app always run in background? This may reduce
        // battery life" dialog in front of someone who asked to share a
        // screen. It is not needed: a foreground service is already exempt
        // from Doze for as long as it runs, and this one runs exactly as long
        // as the share does.
        shouldRequestBatteryOptimizationsOff: false,
      );
      if (!await FlutterBackground.initialize(androidConfig: config)) {
        return false;
      }
      if (FlutterBackground.isBackgroundExecutionEnabled) return true;
      return FlutterBackground.enableBackgroundExecution();
    } catch (e) {
      debugPrint('ScreenCaptureSession: could not prepare – $e');
      return false;
    }
  }

  /// Drops the foreground service once sharing has stopped.
  ///
  /// Deliberately forgiving. This runs on the teardown path, where the share
  /// has already ended one way or another, and leaving a notification behind
  /// is a smaller problem than throwing out of a stop handler.
  static Future<void> release() async {
    if (!HostPlatform.isMobile) return;
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (e) {
      debugPrint('ScreenCaptureSession: could not release – $e');
    }
  }
}
