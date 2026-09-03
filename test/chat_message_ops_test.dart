import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_reaction.dart';
import 'package:rift/logic/services/chat_message_ops.dart';

ChatMessage msg(
  String id, {
  String text = 'hi',
  bool mine = false,
  bool pending = false,
  List<MessageReaction> reactions = const [],
}) => ChatMessage(
  id: id,
  authorId: mine ? 'me' : 'them',
  authorName: mine ? 'Me' : 'Them',
  text: text,
  sentAt: DateTime.utc(2026, 1, 1),
  isMine: mine,
  isPending: pending,
  reactions: reactions,
);

void main() {
  group('id scanning', () {
    test('latestId ignores pending bubbles', () {
      final messages = [msg('7'), msg('12'), msg('pending-0', pending: true)];
      expect(ChatMessageOps.latestId(messages), 12);
    });

    test('oldestId is the pagination cursor', () {
      expect(ChatMessageOps.oldestId([msg('7'), msg('12')]), 7);
    });

    test('the empty-list sentinel is above every id and web-safe', () {
      // Seeds a running minimum and reaches the API as "everything before
      // this", so it has to sit above any real id — an empty list must ask
      // for the newest page, not for nothing.
      final sentinel = ChatMessageOps.oldestId(const []);
      expect(sentinel, greaterThan(ChatMessageOps.oldestId([msg('999999')])));

      // On the web an `int` *is* a double. The sentinel was the 64-bit
      // maximum, which has no exact double — dart2js refused to compile the
      // literal and took the whole web build down with it. Anything that
      // survives this round-trip compiles and compares the same on every
      // target.
      expect(sentinel.toDouble().toInt(), sentinel);
    });

    test('ackedIds drops non-numeric ids', () {
      final ids = ChatMessageOps.ackedIds([
        msg('7'),
        msg('pending-0', pending: true),
      ]);
      expect(ids, [7]);
    });
  });

  group('mergeIncoming', () {
    test('drops rows already held', () {
      final current = [msg('1'), msg('2')];
      final result = ChatMessageOps.mergeIncoming(
        current: current,
        incoming: [msg('2'), msg('3')],
      );
      expect(result.fresh.map((m) => m.id), ['3']);
      expect(result.merged.map((m) => m.id), ['1', '2', '3']);
    });

    test('retires the pending bubble whose text came back', () {
      final current = [
        msg('1'),
        msg('pending-0', text: 'yo', mine: true, pending: true),
        msg('pending-1', text: 'other', mine: true, pending: true),
      ];
      final result = ChatMessageOps.mergeIncoming(
        current: current,
        incoming: [msg('2', text: 'yo', mine: true)],
      );
      // The matching bubble is replaced; the unrelated in-flight one stays.
      expect(result.merged.map((m) => m.id), ['1', 'pending-1', '2']);
    });

    test('one arriving row retires one bubble, not every matching one', () {
      // Two identical sends in flight; the first comes back on someone else's
      // doorbell. The second bubble has to survive, or its own acknowledgement
      // finds nothing to replace and the message is lost from the screen.
      final result = ChatMessageOps.mergeIncoming(
        current: [
          msg('1'),
          msg('pending-0', text: 'ok', mine: true, pending: true),
          msg('pending-1', text: 'ok', mine: true, pending: true),
        ],
        incoming: [msg('2', text: 'ok', mine: true)],
      );
      expect(result.merged.map((m) => m.id), ['1', 'pending-1', '2']);
    });

    test('both bubbles go when both rows come back at once', () {
      final result = ChatMessageOps.mergeIncoming(
        current: [
          msg('pending-0', text: 'ok', mine: true, pending: true),
          msg('pending-1', text: 'ok', mine: true, pending: true),
        ],
        incoming: [
          msg('2', text: 'ok', mine: true),
          msg('3', text: 'ok', mine: true),
        ],
      );
      expect(result.merged.map((m) => m.id), ['2', '3']);
    });

    test("someone else's identical message retires nothing", () {
      final result = ChatMessageOps.mergeIncoming(
        current: [msg('pending-0', text: 'ok', mine: true, pending: true)],
        incoming: [msg('2', text: 'ok')],
      );
      expect(result.merged.map((m) => m.id), ['pending-0', '2']);
    });

    test('nothing fresh leaves the list untouched', () {
      final current = [msg('1')];
      final result = ChatMessageOps.mergeIncoming(
        current: current,
        incoming: [msg('1')],
      );
      expect(result.fresh, isEmpty);
      expect(result.merged, same(current));
    });
  });

  group('pending', () {
    test('replacePending swaps in the acknowledged row', () {
      final messages = [msg('1'), msg('pending-0', mine: true, pending: true)];
      final result = ChatMessageOps.replacePending(
        messages,
        pendingId: 'pending-0',
        acked: msg('2', mine: true),
      );
      expect(result.map((m) => m.id), ['1', '2']);
      expect(result.last.isPending, isFalse);
    });

    test('removePending drops only that bubble', () {
      final messages = [msg('1'), msg('pending-0', pending: true)];
      expect(
        ChatMessageOps.removePending(messages, 'pending-0').map((m) => m.id),
        ['1'],
      );
    });
  });

  group('replaceMessage', () {
    test('swaps the row in place, keeping its position', () {
      final result = ChatMessageOps.replaceMessage([
        msg('1'),
        msg('2', text: 'before'),
        msg('3'),
      ], msg('2', text: 'after'));
      expect(result.map((m) => m.id), ['1', '2', '3']);
      expect(result[1].text, 'after');
    });

    test('a message we do not hold is not appended', () {
      // The edited row can sit outside the loaded window; dropping it on the
      // end would render it out of order.
      final result = ChatMessageOps.replaceMessage([msg('1')], msg('99'));
      expect(result.map((m) => m.id), ['1']);
    });

    test('leaves the other rows identical', () {
      final first = msg('1');
      final result = ChatMessageOps.replaceMessage([
        first,
        msg('2'),
      ], msg('2', text: 'edited'));
      expect(result.first, same(first));
    });
  });
}
