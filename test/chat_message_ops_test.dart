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

  group('reactions', () {
    test('withReactions replaces counts and clears missing ones', () {
      final messages = [
        msg(
          '1',
          reactions: [const MessageReaction(emoji: '👍', count: 9, mine: true)],
        ),
        msg('2'),
      ];
      final merged = ChatMessageOps.withReactions(messages, {
        'reactions': {
          '2': [
            {'emoji': '🔥', 'count': 2, 'mine': false},
          ],
        },
      });
      expect(merged[0].reactions, isEmpty);
      expect(merged[1].reactions.single.emoji, '🔥');
      expect(merged[1].reactions.single.count, 2);
    });

    test('optimistic add creates a mine-flagged chip', () {
      final result = ChatMessageOps.withOptimisticReaction(
        [msg('1')],
        messageId: '1',
        emoji: '👍',
      );
      expect(result.single.reactions.single.count, 1);
      expect(result.single.reactions.single.mine, isTrue);
    });

    test("optimistic add joins someone else's reaction", () {
      final result = ChatMessageOps.withOptimisticReaction(
        [
          msg(
            '1',
            reactions: [
              const MessageReaction(emoji: '👍', count: 1, mine: false),
            ],
          ),
        ],
        messageId: '1',
        emoji: '👍',
      );
      expect(result.single.reactions.single.count, 2);
      expect(result.single.reactions.single.mine, isTrue);
    });

    test('optimistic remove drops the chip when I was the only one', () {
      final result = ChatMessageOps.withOptimisticReaction(
        [
          msg(
            '1',
            reactions: [
              const MessageReaction(emoji: '👍', count: 1, mine: true),
            ],
          ),
        ],
        messageId: '1',
        emoji: '👍',
      );
      expect(result.single.reactions, isEmpty);
    });

    test('optimistic remove leaves the others behind', () {
      final result = ChatMessageOps.withOptimisticReaction(
        [
          msg(
            '1',
            reactions: [
              const MessageReaction(emoji: '👍', count: 3, mine: true),
            ],
          ),
        ],
        messageId: '1',
        emoji: '👍',
      );
      expect(result.single.reactions.single.count, 2);
      expect(result.single.reactions.single.mine, isFalse);
    });

    test('other messages are untouched', () {
      final result = ChatMessageOps.withOptimisticReaction(
        [msg('1'), msg('2')],
        messageId: '1',
        emoji: '👍',
      );
      expect(result[1].reactions, isEmpty);
    });
  });

  group('ChatMessageOps.splitPage', () {
    List<int> rows(int count) => List.generate(count, (i) => i);

    test('the spare row is dropped and reported as more history', () {
      final page = ChatMessageOps.splitPage(rows(4), limit: 3);
      expect(page.rows, [0, 1, 2]);
      expect(page.hasMore, isTrue);
    });

    test('a page exactly the limit long is the end — the old bug', () {
      // 50 messages used to promise a fifty-first, and the reader who scrolled
      // back got a spinner for a page that came back empty.
      final page = ChatMessageOps.splitPage(rows(3), limit: 3);
      expect(page.rows, [0, 1, 2]);
      expect(page.hasMore, isFalse);
    });

    test('a short page is passed through', () {
      final page = ChatMessageOps.splitPage(rows(2), limit: 3);
      expect(page.rows, [0, 1]);
      expect(page.hasMore, isFalse);
    });

    test('no rows at all', () {
      final page = ChatMessageOps.splitPage(<int>[], limit: 3);
      expect(page.rows, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('defaults to the shared page size', () {
      expect(
        ChatMessageOps.splitPage(rows(ChatMessageOps.pageSize + 1)).hasMore,
        isTrue,
      );
      expect(
        ChatMessageOps.splitPage(rows(ChatMessageOps.pageSize)).hasMore,
        isFalse,
      );
    });
  });
}
