part of 'notification_service.dart';

/// A DM call's notifications: the ring on a phone, the notice on a desktop,
/// the missed call in their place, and what a press on one says.
///
/// Its own part because a call is posted, replaced and taken down again,
/// where a message is posted and left; on Windows it is not even the same
/// toast (`api/toast.rs`).
mixin _CallNotificationsMixin {
  FlutterLocalNotificationsPlugin get _plugin;
  bool get _ready;
  String? get _windowsAppId;

  Future<void> showMessage({
    required String title,
    required String body,
    int? id,
    bool chime = true,
    String? payload,
  });

  static const _answerAction = 'answer';
  static const _declineAction = 'decline';

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
      AndroidNotificationAction(_declineAction, 'Decline'),
      AndroidNotificationAction(
        _answerAction,
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

  /// The group a call's notice goes in on Windows ([showCallNotice]).
  static const _windowsCallGroup = 'call';

  /// A desktop's notice about a DM call — "… is calling", or "Missed call"
  /// in its place — posted as the call's one notification, so [cancelCall]
  /// can take it down and a missed call replaces the ring.
  ///
  /// Windows posts it through the Rust library rather than the plugin. An
  /// unpackaged app's toast can only be removed by tag, group and app id
  /// together, and the plugin's toasts have no group (`api/toast.rs`).
  Future<void> showCallNotice({
    required String callId,
    required String title,
    required String body,
    bool chime = true,
  }) async {
    final windowsAppId = _windowsAppId;
    if (!_ready || windowsAppId == null) {
      return showMessage(
        title: title,
        body: body,
        chime: chime,
        id: callNotificationId(callId),
      );
    }
    if (chime) unawaited(SoundService.instance.play(AppSound.message));
    try {
      await showWindowsToast(
        appId: windowsAppId,
        tag: '${callNotificationId(callId)}',
        group: _windowsCallGroup,
        xml: NotificationService.windowsToastXml(title: title, body: body),
      );
    } catch (e) {
      HelperMethods.printDebug('NotificationService: call notice failed – $e');
    }
  }

  /// Take a call's notification down: answered, declined, or over — on a
  /// phone the push's, on a desktop [showCallNotice]'s. The desktop's used to
  /// stay up saying somebody was calling after the call had ended.
  Future<void> cancelCall(String callId) async {
    if (!_ready || kIsWeb) return;
    final id = callNotificationId(callId);
    try {
      final windowsAppId = _windowsAppId;
      if (windowsAppId != null) {
        await removeWindowsToast(
          appId: windowsAppId,
          tag: '$id',
          group: _windowsCallGroup,
        );
      } else {
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      HelperMethods.printDebug('NotificationService: cancel failed – $e');
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

  bool get answers => action == _CallNotificationsMixin._answerAction;
  bool get declines => action == _CallNotificationsMixin._declineAction;
}
