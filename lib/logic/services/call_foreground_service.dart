import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'host_platform.dart';

/// The Android foreground service that keeps a call alive, and the one that
/// lets a screen be captured.
///
/// **LiveKit does not do this.** Its Android plugin manages audio focus and
/// routing and nothing else — there is no foreground service anywhere in the
/// SDK. What that buys is a call that survives being backgrounded for a
/// while: the process is holding audio focus and an open recorder, so the
/// system is in no hurry. It is not a promise. Left long enough, or on a
/// device in Doze, the process is killed and the call goes with it.
///
/// A capture is stricter. From Android 14 MediaProjection is refused outright
/// unless a foreground service declaring `mediaProjection` is *already*
/// running, which is why sharing and calling cannot share one declaration:
///
/// - a call can satisfy `microphone` (RECORD_AUDIO is granted) and nothing
///   else, so that is all it may declare;
/// - a capture can satisfy `mediaProjection` only after the user has answered
///   the system consent sheet.
///
/// Declare both at once and every plain call would be starting a service
/// whose `mediaProjection` prerequisite is unmet. So the manifest lists both
/// types as what this service *may* be, and each start says which of them it
/// actually is. The service is restarted rather than amended when sharing
/// begins, because the type is fixed at `startForeground`.
///
/// A no-op off Android. Desktops do not evict a running app, and iOS wants a
/// different mechanism entirely.
class CallForegroundService {
  const CallForegroundService._();

  static bool _initialised = false;

  /// Whether a share is running, so stopping one knows whether to drop the
  /// service or fall back to the call's own.
  static bool _sharing = false;

  static void _ensureInitialised() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rift_call',
        channelName: 'Ongoing call',
        channelDescription:
            'Shown while a call is connected, so Android keeps it running.',
        // Low: the notification is the price of staying alive, not news. It
        // must exist and must not buzz.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Nothing to run on a timer. The service exists to hold the process
        // up, and the call itself is driven from the main isolate.
        eventAction: ForegroundTaskEventAction.nothing(),
        // The call cannot outlive the app, so neither should this. Without it
        // a swiped-away app leaves a notification for a call that is over.
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
    _initialised = true;
  }

  static Future<void> _restart(List<ForegroundServiceTypes> types) async {
    _ensureInitialised();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    await FlutterForegroundTask.startService(
      serviceTypes: types,
      notificationTitle: _sharing ? 'Sharing your screen' : 'In a call',
      notificationText: _sharing
          ? 'Your screen is visible to everyone in the call.'
          : 'Rift is keeping your call connected.',
    );
  }

  /// Holds the process up for the duration of a call.
  static Future<void> callStarted() async {
    if (!HostPlatform.isMobile) return;
    try {
      _sharing = false;
      await _restart([ForegroundServiceTypes.microphone]);
    } catch (e) {
      // A call that runs without the service is still a call — it is only
      // less likely to survive the app being put away. Not worth refusing to
      // connect over.
      debugPrint('CallForegroundService: could not start – $e');
    }
  }

  /// Adds `mediaProjection`, which has to be running *before* the capture
  /// starts. Returns whether it is now in force: false means the capture
  /// should not be attempted, because Android will refuse it.
  static Future<bool> screenShareStarting() async {
    if (!HostPlatform.isMobile) return true;
    try {
      _sharing = true;
      await _restart([
        ForegroundServiceTypes.mediaProjection,
        ForegroundServiceTypes.microphone,
      ]);
      return true;
    } catch (e) {
      _sharing = false;
      debugPrint('CallForegroundService: could not add mediaProjection – $e');
      return false;
    }
  }

  /// Drops back to the call's own service once sharing ends.
  static Future<void> screenShareStopped() async {
    if (!HostPlatform.isMobile || !_sharing) return;
    _sharing = false;
    try {
      await _restart([ForegroundServiceTypes.microphone]);
    } catch (e) {
      debugPrint('CallForegroundService: could not drop back – $e');
    }
  }

  /// The call is over; nothing is holding the process up any more.
  static Future<void> callEnded() async {
    if (!HostPlatform.isMobile) return;
    _sharing = false;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('CallForegroundService: could not stop – $e');
    }
  }
}
