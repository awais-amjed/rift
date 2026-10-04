/// The native half of [browser_apis.dart]. Every entry point is a no-op.
///
/// Callers do not branch on the platform: `NotificationService` asks for
/// permission and posts through these on every target, and the ones that have a
/// real notification stack simply never reach them because the service takes
/// its own path first. Keeping the signatures identical is the whole point —
/// the branch lives in the export, not in the call sites.
library;

/// Asks the browser for notification permission. Always false off the web.
Future<bool> requestBrowserNotificationPermission() async => false;

/// Posts a browser notification. Does nothing off the web.
void showBrowserNotification({required String title, required String body}) {}

/// Reports tab focus changes. Never fires off the web, where `window_manager`
/// feeds `WindowFocusService` instead.
void startBrowserFocusTracking(void Function(bool focused) onChanged) {}

/// Puts the page in full screen, or takes it out. Does nothing off the web.
Future<void> setBrowserFullscreen(bool on) async {}
