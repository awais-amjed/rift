import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/chat_notice.dart';
import 'package:rift/logic/services/push_wake/wake_item.dart';

WakeItem item(String scope) => WakeItem(
  scope: scope,
  messageId: 1,
  notice: const ChatNotice(title: 't', body: 'b'),
);

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
    for (final scope in ['a', 'dm:s1:u2', 'channel:${'x' * 200}']) {
      final id = item(scope).notificationId;
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThanOrEqualTo(0x7fffffff));
    }
  });
}
