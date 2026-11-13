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

/// Puts the page in full screen, or takes it out.
///
/// The browser only allows it in answer to a click, which is the only place
/// this is called from. It may still say no — an iframe without permission —
/// and the stream then simply fills the tab.
Future<void> setBrowserFullscreen(bool on) async {
  try {
    final active = web.document.fullscreenElement != null;
    if (on && !active) {
      await web.document.documentElement?.requestFullscreen().toDart;
    } else if (!on && active) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (e) {
    HelperMethods.printDebug('browser full screen unavailable – $e');
  }
}

/// Whether the browser encodes H264 for a call in hardware, as its media
/// capabilities say (`powerEfficient`) for a 1080p30 picture.
///
/// No answer is no: headless Chrome, with no GPU, never answers at all, and a
/// browser without the API is one this cannot tell about.
Future<bool> browserEncodesH264InHardware() async {
  try {
    final info = await web.window.navigator.mediaCapabilities
        .encodingInfo(
          web.MediaEncodingConfiguration(
            type: 'webrtc',
            video: web.VideoConfiguration(
              contentType: 'video/H264',
              width: 1920,
              height: 1080,
              bitrate: 6000000,
              framerate: 30,
            ),
          ),
        )
        .toDart
        .timeout(const Duration(seconds: 1));
    HelperMethods.printDebug(
      '[LiveKit] Browser H264: supported ${info.supported}, '
      'hardware ${info.powerEfficient}',
    );
    return info.supported && info.powerEfficient;
  } catch (e) {
    HelperMethods.printDebug('[LiveKit] Browser H264 hardware unknown: $e');
    return false;
  }
}
