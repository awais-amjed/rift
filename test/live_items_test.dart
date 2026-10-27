import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/poll.dart';
import 'package:rift/logic/services/live_items.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  ChatMessage message(
    String id, {
    Duration? closesIn,
    String text = '',
    bool locked = false,
    bool pending = false,
  }) => ChatMessage(
    id: id,
    authorId: 'a',
    authorName: 'A',
    text: text,
    sentAt: now,
    isMine: false,
    isLocked: locked,
    isPending: pending,
    poll: closesIn == null
        ? null
        : Poll(
            question: 'Q$id',
            options: const ['x', 'y'],
            multiple: false,
            closesAt: now.add(closesIn),
          ),
  );

  group('merge', () {
    test('merge uses the loaded page when the server has no answer', () {
      final merged = LiveItems.merge(
        fromServer: null,
        loaded: [
          message('5', closesIn: const Duration(hours: 1)),
          message('4'),
          message('3', closesIn: const Duration(hours: 2)),
        ],
      );
      expect(merged.map((m) => m.id), ['5', '3']);
    });

    test('merge keeps one copy per id, the loaded one', () {
      final merged = LiveItems.merge(
        fromServer: [
          message('7', closesIn: const Duration(hours: 1), text: 'server'),
        ],
        loaded: [
          message('7', closesIn: const Duration(hours: 1), text: 'loaded'),
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.text, 'loaded');
    });

    test('merge orders newest first', () {
      final merged = LiveItems.merge(
        fromServer: [
          message('9', closesIn: const Duration(hours: 1)),
          message('2', closesIn: const Duration(hours: 1)),
        ],
        loaded: [message('10', closesIn: const Duration(hours: 1))],
      );
      expect(merged.map((m) => m.id), ['10', '9', '2']);
    });
  });

  group('open polls', () {
    test('openPolls drops a closed poll and a locked one', () {
      final open = LiveItems.openPolls([
        message('4', closesIn: const Duration(hours: 1)),
        message('3', closesIn: const Duration(hours: -1)),
        message('2', closesIn: const Duration(hours: 1), locked: true),
        message('1', closesIn: const Duration(hours: 1), pending: true),
        message('0'),
      ], now);
      expect(open.map((m) => m.id), ['4']);
    });

    test('nextClose is the soonest future close', () {
      final polls = [
        message('3', closesIn: const Duration(hours: 5)),
        message('2', closesIn: const Duration(minutes: 30)),
        message('1', closesIn: const Duration(hours: -1)),
      ];
      expect(
        LiveItems.nextClose(polls, now),
        now.add(const Duration(minutes: 30)),
      );
      expect(LiveItems.nextClose(const [], now), isNull);
    });
  });
}
