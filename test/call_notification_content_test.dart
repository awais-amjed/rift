import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_notification_content.dart';

/// Once the app is off screen the notification *is* the call: it is the only
/// place left that says which one you are in and the only place you can act on
/// it. "In a call" said neither, which is what this replaces.
void main() {
  test('it names the channel and the server', () {
    final content = callNotificationContent(
      channelName: 'voice',
      serverName: 'T3',
      micEnabled: true,
      sharing: false,
    );

    expect(content.title, 'voice');
    expect(content.text, contains('T3'));
  });

  test('it says whether the mic is on', () {
    final on = callNotificationContent(
      channelName: 'voice',
      micEnabled: true,
      sharing: false,
    );
    final off = callNotificationContent(
      channelName: 'voice',
      micEnabled: false,
      sharing: false,
    );

    expect(on.text, 'Mic on');
    expect(off.text, 'Muted');
  });

  test('the button offers the other state, not the current one', () {
    // Pressing a button labelled "Muted" while muted is a coin flip.
    expect(
      callNotificationContent(micEnabled: true, sharing: false).muteLabel,
      'Mute',
    );
    expect(
      callNotificationContent(micEnabled: false, sharing: false).muteLabel,
      'Unmute',
    );
  });

  test('a screen leaving the device outranks the channel name', () {
    final content = callNotificationContent(
      channelName: 'voice',
      serverName: 'T3',
      micEnabled: true,
      sharing: true,
    );

    expect(content.title, 'Sharing your screen');
    expect(content.text, contains('visible'));
  });

  test('a share still offers the mic button', () {
    // Sharing does not mean you have stopped talking.
    expect(
      callNotificationContent(micEnabled: false, sharing: true).muteLabel,
      'Unmute',
    );
  });

  test('a call with no name is still a call', () {
    // The notification is what holds the process up; it cannot be blank.
    final content = callNotificationContent(micEnabled: true, sharing: false);

    expect(content.title, isNotEmpty);
    expect(content.text, isNotEmpty);
  });
}
