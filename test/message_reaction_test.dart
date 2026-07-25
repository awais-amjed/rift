import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_reaction.dart';

void main() {
  group('MessageReaction.fromJson', () {
    test('parses emoji/count/mine', () {
      final r = MessageReaction.fromJson({
        'emoji': '👍',
        'count': 3,
        'mine': true,
      });
      expect(r.emoji, '👍');
      expect(r.count, 3);
      expect(r.mine, isTrue);
    });

    test('defaults mine to false when absent', () {
      final r = MessageReaction.fromJson({'emoji': '🔥', 'count': 1});
      expect(r.mine, isFalse);
    });
  });

  group('ChatMessage.copyWith(reactions)', () {
    final base = ChatMessage(
      id: '7',
      authorId: 'u1',
      authorName: 'Ada',
      text: 'hi',
      sentAt: DateTime.utc(2026),
      isMine: false,
    );

    test('replaces reactions and preserves everything else', () {
      final updated = base.copyWith(
        reactions: const [MessageReaction(emoji: '🎉', count: 2, mine: false)],
      );
      expect(updated.reactions, hasLength(1));
      expect(updated.reactions.single.emoji, '🎉');
      // unchanged fields
      expect(updated.id, '7');
      expect(updated.text, 'hi');
      expect(updated.authorName, 'Ada');
      // original is untouched (immutability)
      expect(base.reactions, isEmpty);
    });

    test('omitting reactions keeps the existing list', () {
      final withReacts = base.copyWith(
        reactions: const [MessageReaction(emoji: '❤️', count: 1, mine: true)],
      );
      final again = withReacts.copyWith();
      expect(again.reactions, hasLength(1));
      expect(again.reactions.single.emoji, '❤️');
    });
  });
}
