import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/notification_ids.dart';

void main() {
  // A press on a message notification used to open nothing: no payload was
  // posted with one. What a press opens is only as good as this round trip.
  test('each kind of conversation comes back from its payload', () {
    final channel = ConversationNotificationPayload.decode(
      const ConversationNotificationPayload.channel('s1', 'c1').encode(),
    )!;
    expect(channel.isChannel, isTrue);
    expect((channel.serverId, channel.targetId), ('s1', 'c1'));

    final serverDm = ConversationNotificationPayload.decode(
      const ConversationNotificationPayload.serverDm('s1', 'p1').encode(),
    )!;
    expect(serverDm.isServerDm, isTrue);
    expect((serverDm.serverId, serverDm.targetId), ('s1', 'p1'));

    final centralDm = ConversationNotificationPayload.decode(
      const ConversationNotificationPayload.centralDm('p2').encode(),
    )!;
    expect(centralDm.isCentralDm, isTrue);
    expect(centralDm.targetId, 'p2');
  });

  test('anything else is not a conversation', () {
    expect(ConversationNotificationPayload.decode(null), isNull);
    expect(ConversationNotificationPayload.decode(''), isNull);
    expect(ConversationNotificationPayload.decode('dmcall|s1|call1'), isNull);
    expect(ConversationNotificationPayload.decode('chan||c1'), isNull);
    expect(ConversationNotificationPayload.decode('chan|s1|'), isNull);
  });

  // The app and a push wake post a conversation's notification under the
  // same id, and the wake keeps its marks under the same scope — so a phone
  // shows one notification per conversation, whoever posted it.
  test('a conversation names itself as a wake does', () {
    expect(
      const ConversationNotificationPayload.channel('s1', 'c1').scope,
      'channel:s1:c1',
    );
    expect(
      const ConversationNotificationPayload.serverDm('s1', 'p1').scope,
      'dm:s1:p1',
    );
    expect(
      const ConversationNotificationPayload.centralDm('p2').scope,
      'central:p2',
    );
    expect(
      const ConversationNotificationPayload.channel('s1', 'c1').notificationId,
      stableNotificationId('channel:s1:c1'),
    );
    expect(
      const ConversationNotificationPayload.channel('s1', 'x').notificationId,
      isNot(
        const ConversationNotificationPayload.serverDm(
          's1',
          'x',
        ).notificationId,
      ),
    );
  });
}
