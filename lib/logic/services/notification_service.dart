import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

import '../../data/enums/app_sound.dart';
import '../helper_methods.dart';
import 'browser_apis.dart';
import 'notification_ids.dart';
import 'push_wake/call_notification_actions.dart';
import 'sound_service.dart';
import 'storage_namespace.dart';
import 'toast_activator.dart';
import 'toast_identity.dart';
import 'window_focus_service.dart';

/// Local notifications for incoming chat messages, on Linux, Windows, macOS,
/// Android and the web.
///
/// Notifications are only surfaced while the window is unfocused — the trigger
/// sites in the chat cubits gate on [WindowFocusService.isFocused] before
/// calling [showMessage]. The service itself is a thin wrapper around
/// `flutter_local_notifications`, and a no-op before [init] completes.
///
/// The web goes through the browser's own `Notification` API instead
/// (`browser_apis.dart`), because `flutter_local_notifications` has no web
/// support. That is a *page* notification, not a push one: it exists only while
/// the tab does, which is the intended scope — nothing is registered with a
/// push service and nothing arrives while the app is closed.
///
/// Android differs from the desktops in three ways, all of them the
/// platform's: every notification belongs to a **channel**, which is what the
/// user silences rather than the app as a whole; posting them needs a runtime
/// **permission** from API 33; and "unfocused" means the app is not on screen
/// at all rather than merely behind another window.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 0;

  /// Initialize once, before `runApp`. Safe on every platform.
  ///
  /// [askForPermission] exists for the push background isolate, which has no
  /// Activity behind it: asking there throws on a null context, and asking is
  /// pointless anyway because the permission is a property of the app, already
  /// settled by the UI. See [_requestAndroidPermission].
  Future<void> init({bool askForPermission = true}) async {
    if (_ready) return;
    if (kIsWeb) {
      // Deliberately not awaited. The browser's permission promise does not
      // settle until the user answers the prompt, so awaiting it here holds
      // the app on its splash screen for as long as the prompt goes ignored —
      // which is exactly what happened the first time this shipped. Posting is
      // gated on the permission at the call site instead, so an unanswered or
      // refused prompt costs notifications, not the whole app.
      unawaited(requestBrowserNotificationPermission());
      _ready = true;
      return;
    }
    try {
      final linux = LinuxInitializationSettings(
        defaultActionName: 'Open',
        defaultIcon: AssetsLinuxIcon('assets/images/tray_icon.png'),
      );
      // appUserModelId groups toasts under the Rift identity in the Windows
      // Action Center, and the GUID names the class a press is delivered to —
      // one pair per storage namespace (ToastIdentity). The icon is a file
      // path Windows reads itself, so it points at the bundled asset on disk;
      // without one, toasts and their Action Center group have none.
      final identity = ToastIdentity.forSuffix(
        Platform.isWindows ? StorageNamespace.apply() : '',
      );
      final windows = WindowsInitializationSettings(
        appName: identity.appName,
        appUserModelId: identity.appUserModelId,
        guid: identity.guid,
        iconPath: Platform.isWindows ? _windowsIconPath() : null,
      );
      if (Platform.isWindows) _registerActivator(identity);
      // The launcher icon rather than a dedicated one: Android tints a
      // notification icon to a flat silhouette, so a detailed mark would come
      // out as a blob either way.
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // macOS asks its permission inside initialize, so nothing is requested
      // separately. Badges are left out: the dock icon has no count to show.
      const macOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: false,
      );
      await _plugin.initialize(
        settings: InitializationSettings(
          linux: linux,
          windows: windows,
          macOS: macOS,
          android: android,
        ),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: callActionInBackground,
      );
      // Ready before the permission is asked for, and the ask cannot unset it.
      // A refused or unavailable permission costs notifications; it must not
      // cost the plugin's initialization, or a failure to *ask* silently
      // disables posting even where permission was granted long ago.
      _ready = true;
      if (askForPermission) await _requestAndroidPermission();
    } catch (e) {
      HelperMethods.printDebug('NotificationService: init failed – $e');
    }
  }

  /// Without this, Windows never delivers a press (`registerToastActivator`).
  /// A failure costs presses, not notifications, so it is only logged.
  static void _registerActivator(ToastIdentity identity) {
    try {
      registerToastActivator(
        identity.guid,
        ToastIdentity.launchCommand(
          Platform.resolvedExecutable,
          profile: StorageNamespace.explicitProfile,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('NotificationService: activator – $e');
    }
  }

  /// The tray icon as flutter_assets lays it out beside the executable.
  static String _windowsIconPath() => p.join(
    p.dirname(Platform.resolvedExecutable),
    'data',
    'flutter_assets',
    'assets',
    'images',
    'tray_icon.png',
  );

  /// Asks for permission to post, which Android has required since API 33.
  ///
  /// Asked at startup rather than at the first message, deliberately: the
  /// alternative is a system dialog appearing the instant someone messages
  /// you, on top of the very thing it is about. A refusal is final and needs
  /// no handling here — [showMessage] simply has no effect afterwards.
  Future<void> _requestAndroidPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } catch (e) {
      // Throws where there is no Activity to attach a dialog to — a background
      // isolate woken by a push, most of all. Nothing to do about it there and
      // nothing worth failing over.
      HelperMethods.printDebug(
        'NotificationService: permission request skipped – $e',
      );
    }
  }

  // ── Calls ─────────────────────────────────────────────────

  static const answerAction = 'answer';
  static const declineAction = 'decline';

  /// Presses on a call's notification while the app is running: Answer,
  /// Decline, or the notification itself. The app routes them to the call
  /// cubit (`CallNotificationRouter`).
  Stream<CallNotificationPress> get callPresses => _callPresses.stream;
  final StreamController<CallNotificationPress> _callPresses =
      StreamController.broadcast();

  /// Presses on a message notification, carrying the conversation it is
  /// about — null for one posted without saying. The app brings itself
  /// forward and opens it (`ConversationNotificationRouter`).
  Stream<ConversationNotificationPayload?> get messagePresses =>
      _messagePresses.stream;
  final StreamController<ConversationNotificationPayload?> _messagePresses =
      StreamController.broadcast();

  void _onResponse(NotificationResponse response) {
    final press = CallNotificationPress.of(response);
    if (press != null) {
      _callPresses.add(press);
      return;
    }
    final target = ConversationNotificationPayload.decode(response.payload);
    if (_messagePresses.hasListener) {
      _messagePresses.add(target);
    } else {
      _unclaimedPress = (target: target);
    }
  }

  /// A press on a message notification that arrived before anything listened
  /// for one, taken once. On Windows a press with Rift closed starts Rift to
  /// deliver it, and it lands during startup, long before the home screen
  /// listens; a broadcast stream would drop it.
  ({ConversationNotificationPayload? target})? takeUnclaimedPress() {
    final press = _unclaimedPress;
    _unclaimedPress = null;
    return press;
  }

  ({ConversationNotificationPayload? target})? _unclaimedPress;

  /// The press that launched the app from nothing, if it was on a call's
  /// notification — answered once, because a launch happens once.
  Future<CallNotificationPress?> takeLaunchPress() async {
    if (_launchTaken || kIsWeb || !Platform.isAndroid) return null;
    _launchTaken = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if (!(details?.didNotificationLaunchApp ?? false) || response == null) {
        return null;
      }
      return CallNotificationPress.of(response);
    } catch (e) {
      HelperMethods.printDebug('NotificationService: launch details – $e');
      return null;
    }
  }

  bool _launchTaken = false;

  /// Calls get a channel of their own, at the top of the scale: a person
  /// waiting on the line is not a message that can sit in the shade, and a
  /// phone owner may well want calls to ring and messages to stay quiet.
  static const _callDetails = AndroidNotificationDetails(
    'rift_calls',
    'Calls',
    channelDescription: 'Somebody calling you in a direct message.',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    ongoing: true,
    autoCancel: false,
    // The server stops a ring at 45 seconds; a notification that outlived
    // it would offer to answer a call that can no longer be answered.
    timeoutAfter: 45000,
    actions: [
      AndroidNotificationAction(declineAction, 'Decline'),
      AndroidNotificationAction(
        answerAction,
        'Answer',
        showsUserInterface: true,
      ),
    ],
  );

  /// A DM call ringing this phone. Android only: this is what a push wake
  /// posts, and a desktop rings in its own window.
  Future<void> showIncomingCall({
    required String serverId,
    required String callId,
    required String peerName,
    required String serverName,
  }) async {
    if (!_ready || kIsWeb || !Platform.isAndroid) return;
    try {
      await _plugin.show(
        id: callNotificationId(callId),
        title: '$peerName is calling',
        body: 'Direct call · $serverName',
        payload: CallNotificationPayload(serverId, callId).encode(),
        notificationDetails: const NotificationDetails(android: _callDetails),
      );
    } catch (e) {
      HelperMethods.printDebug('NotificationService: call failed – $e');
    }
  }

  /// A ring nobody answered, in place of the ringing notification.
  Future<void> showMissedCall({
    required String callId,
    required String peerName,
    required String serverName,
  }) => showMessage(
    title: 'Missed call',
    body: 'From $peerName · $serverName',
    id: callNotificationId(callId),
  );

  /// Take a call's notification down: answered, declined, or over.
  Future<void> cancelCall(String callId) async {
    if (!_ready || kIsWeb || !Platform.isAndroid) return;
    try {
      await _plugin.cancel(id: callNotificationId(callId));
    } catch (e) {
      HelperMethods.printDebug('NotificationService: cancel failed – $e');
    }
  }

  /// The channel every message notification is posted to.
  ///
  /// One channel, not one per server: a channel is what the user silences,
  /// and "messages" is the grain they think in. Its name and importance are
  /// fixed at creation — Android ignores later changes — so this is the only
  /// place they can be chosen.
  static const _androidDetails = AndroidNotificationDetails(
    'rift_messages',
    'Messages',
    channelDescription: 'New direct messages and channel mentions.',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Show a "new message" notification. Title is typically the sender/context
  /// (e.g. "Alice in #general"), body the message preview.
  ///
  /// [id] lets a caller decide what this notification *replaces*. Posting
  /// under the same id twice updates the one already in the shade rather than
  /// stacking a second — which is what the push background isolate wants, one
  /// notification per conversation. The default keeps every call distinct,
  /// which is right for the in-app paths: they fire once per message, in a
  /// process that is alive to keep counting.
  /// [chime] is false for something that makes its own sound — a call,
  /// whose ringtone is already playing. [payload] is what a press on it
  /// opens: a [ConversationNotificationPayload], encoded.
  Future<void> showMessage({
    required String title,
    required String body,
    int? id,
    bool chime = true,
    String? payload,
  }) async {
    if (!_ready) return;
    if (kIsWeb) {
      showBrowserNotification(title: title, body: body);
      return;
    }
    // Every platform [init] configures, and only those. Android was once
    // missing from this list, which quietly cost the platform that needs
    // notifications most every one it should have had. iOS is not set up in
    // [init] yet, so it stays out until it is.
    if (!Platform.isLinux &&
        !Platform.isWindows &&
        !Platform.isMacOS &&
        !Platform.isAndroid) {
      return;
    }
    // On a desktop the chime is Rift's own, so it follows the volume and the
    // mute in settings, and the system's is silenced so there are not two.
    // Android keeps the system's: its channel is where a phone's owner
    // already decides how a notification sounds.
    if (!Platform.isAndroid && chime) {
      unawaited(SoundService.instance.play(AppSound.message));
    }
    try {
      await _plugin.show(
        id: id ?? _nextId++,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          linux: const LinuxNotificationDetails(suppressSound: true),
          windows: WindowsNotificationDetails(
            audio: WindowsNotificationAudio.silent(),
          ),
          macOS: const DarwinNotificationDetails(presentSound: false),
          android: _androidDetails,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('NotificationService: show failed – $e');
    }
  }
}

/// One press on a call's notification.
class CallNotificationPress {
  final CallNotificationPayload call;

  /// `answer`, `decline`, or null for the notification itself.
  final String? action;

  const CallNotificationPress(this.call, this.action);

  static CallNotificationPress? of(NotificationResponse response) {
    final call = CallNotificationPayload.decode(response.payload);
    return call == null ? null : CallNotificationPress(call, response.actionId);
  }

  bool get answers => action == NotificationService.answerAction;
  bool get declines => action == NotificationService.declineAction;
}
