import 'call_notification_task.dart';

/// What the ongoing-call notification says, and what its buttons are labelled.
///
/// Pure, and separate from the service that posts it, because this is the
/// call's whole interface once the app is off screen and the wording is worth
/// pinning down: which call, what the mic is doing, and what pressing a button
/// will do next.
class CallNotificationContent {
  final String title;
  final String text;

  /// The mute button's label. It names the *action*, not the current state —
  /// the convention every media notification follows, and the one that makes a
  /// glance at the shade unambiguous.
  final String muteLabel;

  const CallNotificationContent({
    required this.title,
    required this.text,
    required this.muteLabel,
  });

  /// The button ids, so a press can be matched back to what it meant. Shared
  /// with the handler isolate, which sees nothing but these.
  static const String muteId = kCallMuteButtonId;
  static const String leaveId = kCallLeaveButtonId;
  static const String leaveLabel = 'Leave';
}

/// The notification for the call as it stands.
///
/// A sharing call says so instead of naming the channel: a screen leaving the
/// device is the more consequential of the two facts, and it is the one the
/// user will want to check on from the shade.
CallNotificationContent callNotificationContent({
  String? channelName,
  String? serverName,
  required bool micEnabled,
  required bool sharing,
}) {
  final muteLabel = micEnabled ? 'Mute' : 'Unmute';

  if (sharing) {
    return CallNotificationContent(
      title: 'Sharing your screen',
      text: 'Your screen is visible to everyone in the call.',
      muteLabel: muteLabel,
    );
  }

  final mic = micEnabled ? 'Mic on' : 'Muted';
  return CallNotificationContent(
    // Falls back rather than showing an empty bar: a call with no name is
    // still a call, and the notification is what keeps the process alive.
    title: channelName ?? 'In a call',
    text: serverName == null ? mic : '$serverName · $mic',
    muteLabel: muteLabel,
  );
}
