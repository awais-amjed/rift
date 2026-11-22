import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/chat_notice.dart';
import 'package:rift/logic/services/push_wake/wake_item.dart';

WakeItem item(String scope) => WakeItem(
  target: _target(scope),
  messageId: 1,
  notice: const ChatNotice(title: 't', body: 'b'),
);

/// A conversation from the scope a wake writes for it.
ConversationNotificationPayload _target(String scope) {
  final parts = scope.split(':');
  return switch (parts.first) {
    'channel' => ConversationNotificationPayload.channel(parts[1], parts[2]),
    'dm' => ConversationNotificationPayload.serverDm(parts[1], parts[2]),
    _ => ConversationNotificationPayload.centralDm(parts.last),
  };
}

/// The notification id decides what a wake *replaces*. Every wake is a fresh
/// isolate, so it has to be derived from the conversation rather than counted.
void main() {
  test('the same conversation always gets the same id', () {
    expect(item('dm:s1:u2').notificationId, item('dm:s1:u2').notificationId);
  });

  test('different conversations get different ids', () {
    expect(
      item('dm:s1:u2').notificationId,
      isNot(item('dm:s1:u3').notificationId),
    );
    expect(
      item('channel:s1:c1').notificationId,
      isNot(item('dm:s1:c1').notificationId),
    );
  });

  test('the id is a positive 32-bit int, which is what Android accepts', () {
    for (final scope in ['central:a', 'dm:s1:u2', 'channel:s1:${'x' * 200}']) {
      final id = item(scope).notificationId;
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7fffffff));
    }
  });

  // The ring says nothing, not even which server sent it, so a wake that
  // finds nothing to say must decide whether that silence is an answer.
  group('owesFallback', () {
    final found = (items: [item('channel:s1:c1')], failed: false);

    test('one unreachable server does not speak for a quiet one', () {
      // The bug: a message in a mentions-only channel on one server, read and
      // rightly kept quiet, came out as "You have a new message" because
      // another server on the phone could not be reached.
      expect(
        owesFallback(
          central: emptyHarvest,
          servers: [emptyHarvest, failedHarvest],
        ),
        isFalse,
      );
    });

    test('owed when no server could be read', () {
      expect(
        owesFallback(
          central: emptyHarvest,
          servers: [failedHarvest, failedHarvest],
        ),
        isTrue,
      );
    });

    test('owed when central could not be read', () {
      expect(
        owesFallback(central: failedHarvest, servers: [emptyHarvest]),
        isTrue,
      );
    });

    test('owed when there are no servers to ask', () {
      expect(owesFallback(central: emptyHarvest, servers: const []), isTrue);
    });

    test('not owed when everything answered with nothing new', () {
      expect(
        owesFallback(central: emptyHarvest, servers: [emptyHarvest]),
        isFalse,
      );
    });

    test('never owed when something was found to say', () {
      expect(
        owesFallback(central: failedHarvest, servers: [failedHarvest, found]),
        isFalse,
      );
    });
  });
}
