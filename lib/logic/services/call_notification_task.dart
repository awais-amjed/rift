import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// The button that mutes and unmutes, from the notification shade.
const String kCallMuteButtonId = 'mute';

/// The button that leaves the call.
const String kCallLeaveButtonId = 'leave';

/// The background isolate behind the call notification's buttons.
///
/// A foreground service's notification is the only part of a call that is on
/// screen once the app is put away, so the two things worth doing to a call
/// from there — stop talking, hang up — have to be reachable without bringing
/// the app back. Android delivers a button press to the service, and
/// `flutter_foreground_task` hands it to a [TaskHandler] running in an isolate
/// of its own.
///
/// That isolate has no cubits, no room and no state — it is spun up from a bare
/// entry point and shares nothing with the app. So it does the only thing it
/// usefully can: forwards the button's id to the main isolate, where
/// `CallForegroundService` knows what a call is. Which is why the ids above are
/// a shared constant rather than a string typed twice.
@pragma('vm:entry-point')
void callNotificationTask() {
  FlutterForegroundTask.setTaskHandler(_CallNotificationHandler());
}

class _CallNotificationHandler extends TaskHandler {
  // Nothing to set up and nothing to tear down: this handler exists for its
  // button callback alone, and the service is started with an event action of
  // `nothing()` so no timer ever calls the rest of it.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) =>
      FlutterForegroundTask.sendDataToMain(id);
}
