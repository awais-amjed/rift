import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../helper_methods.dart';
import 'call_notification_content.dart';
import 'call_notification_task.dart';
import 'host_platform.dart';

/// Over the helper budget and one job: Android's foreground service for a call
/// — starting it, keeping its notification current, and ending it.
///
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
/// - a call can satisfy `microphone`, because RECORD_AUDIO is granted;
/// - `camera` only once CAMERA has been granted, which does not happen until
///   the camera is first switched on;
/// - `mediaProjection` only after the user has answered the consent sheet.
///
/// Declare all three at once and every plain call would be starting a service
/// with two unmet prerequisites. So the manifest lists them as what this
/// service *may* be, and each start says which of them it actually is — see
/// [_types]. The service is restarted rather than amended when that set
/// changes, because the type is fixed at `startForeground`.
///
/// A type left out is not cosmetic: Android cuts off the hardware it names
/// once the app is in the background. Without `camera` a backgrounded video
/// call keeps its audio and loses its picture.
///
/// The notification it posts is not only the price of admission: once the app
/// is put away it is the whole of the call's user interface, so it names the
/// channel and carries the two controls worth having there — see
/// [callNotificationTask] for how a press gets back here.
///
/// A no-op off Android. Desktops do not evict a running app, and iOS wants a
/// different mechanism entirely.
class CallForegroundService {
  const CallForegroundService._();

  static bool _initialised = false;

  /// Whether a share is running, so stopping one knows whether to drop the
  /// service or fall back to the call's own.
  static bool _sharing = false;

  /// The last set applied, so a change that does not move it does not restart
  /// the service for nothing.
  static List<ForegroundServiceTypes>? _applied;

  /// What the notification is about: which call, and whether the mic is on.
  static String? _channelName;
  static String? _serverName;
  static bool _micEnabled = true;

  /// What its buttons do. Held here rather than passed through the service
  /// because a press arrives long after the call was joined, from an isolate
  /// that knows nothing but a button id.
  static VoidCallback? _onToggleMute;
  static VoidCallback? _onLeave;

  static void _ensureInitialised() {
    if (_initialised) return;
    // The port a button press comes back on. Opened here rather than in main
    // because nothing can send on it until a service exists, and this runs
    // before the first one does.
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
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
        // The one notification the app posts more than once. Re-announcing it
        // on every mute would make a control feel like an alert.
        onlyAlertOnce: true,
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

  /// A button pressed in the shade, forwarded from the handler isolate.
  ///
  /// Anything else on the port is not ours and is ignored rather than guessed
  /// at — the port is shared by whatever else the app might one day run.
  static void _onTaskData(Object data) {
    switch (data) {
      case kCallMuteButtonId:
        _onToggleMute?.call();
      case kCallLeaveButtonId:
        _onLeave?.call();
    }
  }

  /// What the shade should be saying right now — see [callNotificationContent],
  /// which is where the wording lives.
  static CallNotificationContent get _content => callNotificationContent(
    channelName: _channelName,
    serverName: _serverName,
    micEnabled: _micEnabled,
    sharing: _sharing,
  );

  /// Mute and leave: the two things you do to a call you are not looking at.
  static List<NotificationButton> _buttons(CallNotificationContent content) => [
    NotificationButton(
      id: CallNotificationContent.muteId,
      text: content.muteLabel,
    ),
    const NotificationButton(
      id: CallNotificationContent.leaveId,
      text: CallNotificationContent.leaveLabel,
    ),
  ];

  /// What the service may claim right now.
  ///
  /// `camera` is conditional on the permission rather than on the camera
  /// being *on*: the prerequisite Android checks is the grant, and asking for
  /// the type while the camera happens to be off costs nothing while saving a
  /// restart at the moment it is switched on. It is absent until the camera
  /// has been used once, because that is when the grant happens.
  static Future<List<ForegroundServiceTypes>> _types() async {
    return [
      ForegroundServiceTypes.microphone,
      if (await Permission.camera.isGranted) ForegroundServiceTypes.camera,
      if (_sharing) ForegroundServiceTypes.mediaProjection,
    ];
  }

  /// Brings the service in line with what is running, restarting it only when
  /// the set of types has actually moved.
  static Future<void> _apply({bool force = false}) async {
    _ensureInitialised();
    final types = await _types();
    final applied = _applied;
    if (!force &&
        applied != null &&
        applied.length == types.length &&
        applied.toSet().containsAll(types) &&
        await FlutterForegroundTask.isRunningService) {
      return;
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    final content = _content;
    await FlutterForegroundTask.startService(
      serviceTypes: types,
      notificationTitle: content.title,
      notificationText: content.text,
      notificationButtons: _buttons(content),
      callback: callNotificationTask,
    );
    _applied = types;
  }

  /// Rewrites the notification in place.
  ///
  /// Not [_apply]: that restarts the service, which would take
  /// `mediaProjection` away for an instant and end a running capture. Muting
  /// must not stop a screen share.
  static Future<void> _refresh() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final content = _content;
    await FlutterForegroundTask.updateService(
      notificationTitle: content.title,
      notificationText: content.text,
      notificationButtons: _buttons(content),
    );
  }

  /// Holds the process up for the duration of a call, and says in the shade
  /// which call it is.
  static Future<void> callStarted({
    required String channelName,
    String? serverName,
    required bool micEnabled,
    required VoidCallback onToggleMute,
    required VoidCallback onLeave,
  }) async {
    if (!HostPlatform.isMobile) return;
    try {
      _sharing = false;
      _channelName = channelName;
      _serverName = serverName;
      _micEnabled = micEnabled;
      _onToggleMute = onToggleMute;
      _onLeave = onLeave;
      await _apply(force: true);
    } catch (e) {
      // A call that runs without the service is still a call — it is only
      // less likely to survive the app being put away. Not worth refusing to
      // connect over.
      HelperMethods.printDebug('CallForegroundService: could not start – $e');
    }
  }

  /// Adds `mediaProjection`, which has to be running *before* the capture
  /// starts. Returns whether it is now in force: false means the capture
  /// should not be attempted, because Android will refuse it.
  static Future<bool> screenShareStarting() async {
    if (!HostPlatform.isMobile) return true;
    try {
      _sharing = true;
      await _apply();
      return true;
    } catch (e) {
      _sharing = false;
      HelperMethods.printDebug(
        'CallForegroundService: could not add mediaProjection – $e',
      );
      return false;
    }
  }

  /// Drops back to the call's own service once sharing ends.
  static Future<void> screenShareStopped() async {
    if (!HostPlatform.isMobile || !_sharing) return;
    _sharing = false;
    try {
      await _apply();
    } catch (e) {
      HelperMethods.printDebug(
        'CallForegroundService: could not drop back – $e',
      );
    }
  }

  /// The mic has been muted or unmuted, from anywhere — the app, the shade,
  /// or a moderator. The notification says so and its button flips to the
  /// other verb.
  static Future<void> micChanged(bool enabled) async {
    if (!HostPlatform.isMobile || _micEnabled == enabled) return;
    _micEnabled = enabled;
    try {
      await _refresh();
    } catch (e) {
      HelperMethods.printDebug(
        'CallForegroundService: could not follow the mic – $e',
      );
    }
  }

  /// The camera has been switched on or off.
  ///
  /// Only the first switch-on usually matters: that is when CAMERA is granted
  /// and the service can start claiming the type. Skipped entirely while
  /// sharing — restarting the service would take `mediaProjection` away for
  /// an instant, and Android ends a capture whose service has gone. Losing
  /// the camera in the background for the rest of a share is much the smaller
  /// problem, and the share ending re-applies the set anyway.
  static Future<void> cameraChanged() async {
    if (!HostPlatform.isMobile || _sharing) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    try {
      await _apply();
    } catch (e) {
      HelperMethods.printDebug(
        'CallForegroundService: could not follow the camera – $e',
      );
    }
  }

  /// The call is over; nothing is holding the process up any more.
  static Future<void> callEnded() async {
    if (!HostPlatform.isMobile) return;
    _sharing = false;
    _applied = null;
    _channelName = null;
    _serverName = null;
    // Dropped so a press that raced the hang-up cannot reach a call that has
    // already gone.
    _onToggleMute = null;
    _onLeave = null;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      HelperMethods.printDebug('CallForegroundService: could not stop – $e');
    }
  }
}
