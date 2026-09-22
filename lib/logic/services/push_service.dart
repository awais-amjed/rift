import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../helper_methods.dart';
import 'host_platform.dart';
import 'notification_service.dart';
import 'push_wake/push_wake_service.dart';

/// Waking the app for a message that arrived while it was suspended.
///
/// Local notifications only fire while the process is alive, which on Android
/// means they stop the moment the system decides the app has been in the
/// background long enough. Only a push can wake it.
///
/// **The push carries nothing.** Not the sender, not the text, not which
/// server — not even encrypted bytes. It is a doorbell, and the same reasoning
/// applies as to the Realtime doorbells the app already uses: the database is
/// the source of truth, so a ping only has to say "look again".
///
/// That is a privacy decision as much as a design one. An FCM payload is
/// readable by Google, and a relay has to be able to forward it, so anything
/// put in one is disclosed to both. A doorbell discloses that a device was
/// pinged and nothing else — and costs no detail in the notification, because
/// the phone holds the keys and can fetch and decrypt the message itself once
/// it is awake.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// The FCM registration token, once there is one. A [ValueNotifier] rather
  /// than a getter because it arrives asynchronously and can be replaced at
  /// any time — FCM rotates tokens, and a stale one is a phone that has gone
  /// quiet without anyone noticing.
  final ValueNotifier<String?> token = ValueNotifier<String?>(null);

  bool _started = false;

  /// Which store of tokens a registration belongs in. FCM tokens and APNs
  /// tokens are not interchangeable, and a sender has to know which it holds.
  static String get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  /// Whether this build can receive pushes at all. Desktop keeps a process
  /// alive on its own, so it has never needed one.
  static bool get isSupported => HostPlatform.isMobile;

  Future<void> init() async {
    if (_started || !isSupported) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      // Registered before any token exists: the handler is what Android looks
      // up when it wakes the app, and it has to be findable from a cold start.
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      token.value = await messaging.getToken();
      messaging.onTokenRefresh.listen((next) => token.value = next);

      // A push that lands while the app is up needs no notification of its
      // own: the Realtime subscriptions are live and already doing this work,
      // and posting here as well would show everything twice.
      FirebaseMessaging.onMessage.listen((_) {});
    } catch (e) {
      HelperMethods.printDebug('PushService: init failed – $e');
    }
  }
}

/// Runs in a background isolate when a push arrives and the app is not up.
///
/// Top-level and marked as an entry point because Android calls it directly,
/// into a fresh isolate that has none of the app's state — no cubits, no open
/// database connections, nothing that was in memory a moment ago.
///
/// The doorbell says nothing, so this is where the notification is *earned*:
/// [PushWakeService] reads the seed, asks each server what is unread and
/// decrypts the newest message in each conversation, so the shade can name the
/// sender and quote the line. Everything it needs is already on the device,
/// which is exactly why the payload could be empty.
///
/// [DartPluginRegistrant.ensureInitialized] because this isolate is not the
/// one `main` set up: without it, secure storage, shared preferences and the
/// notifications plugin are all method channels with nothing on the other end.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  // No Activity here, so nothing to hang a permission dialog on.
  await NotificationService.instance.init(askForPermission: false);
  await PushWakeService.run();
}
