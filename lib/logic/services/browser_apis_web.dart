/// The web half of [browser_apis.dart] — the real browser calls.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;
import '../helper_methods.dart';

/// Asks the browser for notification permission, returning whether it was
/// granted.
///
/// Chrome requires a user gesture for this prompt in some contexts, and a
/// refusal is permanent until the user changes it in site settings — so this
/// runs once at startup rather than at the first message, for the same reason
/// Android's does: the alternative is a permission prompt appearing on top of
/// the very message it is about.
Future<bool> requestBrowserNotificationPermission() async {
  try {
    switch (web.Notification.permission) {
      case 'granted':
        return true;
      case 'denied':
        return false;
    }
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  } catch (e) {
    // Notification is absent in insecure contexts and some embedded webviews.
    HelperMethods.printDebug('browser notifications unavailable – $e');
    return false;
  }
}

/// Posts a browser notification.
///
/// Deliberately fire-and-forget with no click handler: the tab is already open
/// — that is the only case this is reached in — so there is nothing to launch,
/// and focusing it from here would fight the user's own window management.
void showBrowserNotification({required String title, required String body}) {
  if (web.Notification.permission != 'granted') return;
  try {
    web.Notification(title, web.NotificationOptions(body: body));
  } catch (e) {
    HelperMethods.printDebug('browser notification failed – $e');
  }
}

/// Reports whether the tab is the thing the user is currently looking at.
///
/// Two signals, because neither is enough alone: `visibilitychange` catches a
/// backgrounded tab or a minimised browser but not another window stealing
/// focus on top of a still-visible one, and `focus`/`blur` catch that but not
/// the tab being switched away from. The app is "focused" only when the
/// document is visible *and* holds focus.
void startBrowserFocusTracking(void Function(bool focused) onChanged) {
  void report() {
    final visible = web.document.visibilityState == 'visible';
    onChanged(visible && web.document.hasFocus());
  }

  final listener = ((web.Event _) => report()).toJS;
  web.document.addEventListener('visibilitychange', listener);
  web.window.addEventListener('focus', listener);
  web.window.addEventListener('blur', listener);
  report();
}
