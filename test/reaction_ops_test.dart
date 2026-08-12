import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_reaction.dart';
import 'package:rift/logic/services/reaction_ops.dart';

ChatMessage msg(
  String id, {
  bool mine = false,
  List<MessageReaction> reactions = const [],
}) => ChatMessage(
  id: id,
  authorId: mine ? 'me' : 'them',
  authorName: mine ? 'Me' : 'Them',
  text: 'hi',
  sentAt: DateTime.utc(2026, 1, 1),
  isMine: mine,
  reactions: reactions,
);

void main() {
  group('aggregate', () {
    test('counts each emoji and flags the local user', () {
      final result = ReactionOps.aggregate([
        {'user_id': 'u1', 'emoji': '👍'},
        {'user_id': 'me', 'emoji': '👍'},
        {'user_id': 'u1', 'emoji': '🔥'},
      ], userId: 'me');

      expect(result, [
        {'emoji': '👍', 'count': 2, 'mine': true},
        {'emoji': '🔥', 'count': 1, 'mine': false},
      ]);
    });

    test('a signed-out reader owns nothing', () {
      final result = ReactionOps.aggregate([
        {'user_id': 'u1', 'emoji': '👍'},
      ], userId: null);
      expect(result.single['mine'], isFalse);
    });

    test('no rows is no reactions', () {
      expect(ReactionOps.aggregate(const [], userId: 'me'), isEmpty);
    });
  });

  group('byMessage', () {
    test('groups rows spanning several messages', () {
      final result = ReactionOps.byMessage([
        {'message_id': 1, 'user_id': 'me', 'emoji': '👍'},
        {'message_id': 2, 'user_id': 'u1', 'emoji': '🔥'},
        {'message_id': 1, 'user_id': 'u1', 'emoji': '👍'},
      ], userId: 'me');

      expect(result.keys, ['1', '2']);
      expect((result['1'] as List).single, {
        'emoji': '👍',
        'count': 2,
        'mine': true,
      });
      expect((result['2'] as List).single['mine'], isFalse);
    });
  });

  group('fromRow', () {
    test('reads the aggregated list a message page carried', () {
      final reactions = ReactionOps.fromRow({
        'id': 1,
        'reactions': [
          {'emoji': '👍', 'count': 2, 'mine': true},
        ],
      });
      expect(reactions.single.emoji, '👍');
      expect(reactions.single.count, 2);
      expect(reactions.single.mine, isTrue);
    });

    test('a row without the key has none', () {
      expect(ReactionOps.fromRow({'id': 1}), isEmpty);
    });
  });

  group('withReactionsFor', () {
    test('applies the answer to the named message only', () {
      final messages = [
        msg(
          '1',
          reactions: [const MessageReaction(emoji: '👍', count: 1, mine: true)],
        ),
        msg(
          '2',
          reactions: [
            const MessageReaction(emoji: '🔥', count: 4, mine: false),
          ],
        ),
      ];
      final result = ReactionOps.withReactionsFor(
        messages,
        messageId: '1',
        data: {
          'reactions': {
            '1': [
              {'emoji': '👍', 'count': 2, 'mine': true},
            ],
          },
        },
      );

      expect(result[0].reactions.single.count, 2);
      // The message we didn't ask about keeps what it had — the whole point of
      // a targeted refresh.
      expect(result[1].reactions.single.count, 4);
    });

    test('an absent entry clears that message — the last reaction removed', () {
      final messages = [
        msg(
          '1',
          reactions: [const MessageReaction(emoji: '👍', count: 1, mine: true)],
        ),
      ];
      final result = ReactionOps.withReactionsFor(
        messages,
        messageId: '1',
        data: const {'reactions': {}},
      );
      expect(result.single.reactions, isEmpty);
    });
  });

  group('withReactions', () {
    test('replaces counts and clears messages missing from the map', () {
      final messages = [
        msg(
          '1',
          reactions: [const MessageReaction(emoji: '👍', count: 9, mine: true)],
        ),
        msg('2'),
      ];
      final merged = ReactionOps.withReactions(messages, {
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
  });

  group('withOptimisticReaction', () {
    test('add creates a mine-flagged chip', () {
      final result = ReactionOps.withOptimisticReaction(
        [msg('1')],
        messageId: '1',
        emoji: '👍',
      );
      expect(result.single.reactions.single.count, 1);
      expect(result.single.reactions.single.mine, isTrue);
    });

    test("add joins someone else's reaction", () {
      final result = ReactionOps.withOptimisticReaction(
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

    test('remove drops the chip when I was the only one', () {
      final result = ReactionOps.withOptimisticReaction(
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

    test('remove leaves the others behind', () {
      final result = ReactionOps.withOptimisticReaction(
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
      final result = ReactionOps.withOptimisticReaction(
        [msg('1'), msg('2')],
        messageId: '1',
        emoji: '👍',
      );
      expect(result[1].reactions, isEmpty);
    });
  });
}
