import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/classes/dm_conversation.dart';
import 'window_focus_service.dart';

/// Local notifications for incoming chat messages, on Linux, Windows and
/// Android.
///
/// Notifications are only surfaced while the window is unfocused — the trigger
/// sites in the chat cubits gate on [WindowFocusService.isFocused] before
/// calling [showMessage]. The service itself is a thin wrapper around
/// `flutter_local_notifications`; a no-op on web and before [init] completes.
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

  /// Initialize once, before `runApp`. Safe to call on web (does nothing).
  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      final linux = LinuxInitializationSettings(
        defaultActionName: 'Open',
        defaultIcon: AssetsLinuxIcon('assets/images/tray_icon.png'),
      );
      // The GUID matches the installer app id; appUserModelId groups toasts
      // under the Rift identity in the Windows Action Center.
      const windows = WindowsInitializationSettings(
        appName: 'Rift',
        appUserModelId: 'CodingFries.Rift',
        guid: '919df387-f79b-5d74-bee3-b08f176b2a14',
      );
      // The launcher icon rather than a dedicated one: Android tints a
      // notification icon to a flat silhouette, so a detailed mark would come
      // out as a blob either way.
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: InitializationSettings(
          linux: linux,
          windows: windows,
          android: android,
        ),
      );
      await _requestAndroidPermission();
      _ready = true;
    } catch (e) {
      debugPrint('NotificationService: init failed – $e');
    }
  }

  /// Asks for permission to post, which Android has required since API 33.
  ///
  /// Asked at startup rather than at the first message, deliberately: the
  /// alternative is a system dialog appearing the instant someone messages
  /// you, on top of the very thing it is about. A refusal is final and needs
  /// no handling here — [showMessage] simply has no effect afterwards.
  Future<void> _requestAndroidPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
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
  Future<void> showMessage({
    required String title,
    required String body,
  }) async {
    if (!_ready || kIsWeb) return;
    // Windows has no concept of "any listener" — guard platform anyway so a
    // stray call on an unsupported target is a silent no-op.
    if (!Platform.isLinux && !Platform.isWindows) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
          android: _androidDetails,
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: show failed – $e');
    }
  }
}

/// Diffs successive conversation-list snapshots and fires a notification for
/// each newly-arrived *incoming* message, once, when the window is unfocused.
///
/// DM inbox topics are per-user (not per-conversation), so the conversation
/// list is the one place that learns of new messages across every peer — this
/// rides on the existing `refreshConversations` calls. The first scan after a
/// [reset] only primes the seen-set, so opening the app never replays history
/// as a burst of notifications.
class NewMessageNotifier {
  final Set<String> _seen = <String>{};
  bool _primed = false;

  /// Forget all state — call when the identity/server context changes so the
  /// next scan re-primes instead of notifying for a different account's chats.
  void reset() {
    _seen.clear();
    _primed = false;
  }

  /// Inspect the latest conversation snapshot. [titleFor] builds the
  /// notification title for a conversation (e.g. its peer name).
  void scan(
    Iterable<DmConversation> conversations, {
    required String Function(DmConversation) titleFor,
  }) {
    final fresh = <DmConversation>[];
    for (final convo in conversations) {
      final last = convo.lastMessage;
      if (last == null || last.isMine) continue;
      final key = '${convo.peerId}:${last.id}';
      // add() is true only the first time we see this message. Notify only
      // once primed, so the initial snapshot is absorbed silently.
      if (_seen.add(key) && _primed) fresh.add(convo);
    }
    _primed = true;
    if (fresh.isEmpty || WindowFocusService.instance.isFocused) return;
    for (final convo in fresh) {
      NotificationService.instance.showMessage(
        title: titleFor(convo),
        body: convo.lastMessage!.text,
      );
    }
  }
}
