import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/services/quote_lookup.dart';

/// What a client knows about the message a reply names.
void main() {
  ChatMessage msg(String id) => ChatMessage(
    id: id,
    authorId: 'ana',
    authorName: 'ana',
    text: 'x',
    sentAt: DateTime.utc(2026, 9, 20),
    isMine: false,
  );

  group('QuotedMessage', () {
    test('keeps "not found" and "not there" apart', () {
      // The whole reason the type exists. Telling a reader the second when
      // the first is true says somebody deleted something they did not.
      const unknown = QuotedMessage.unknown();
      const deleted = QuotedMessage.deleted();
      final found = QuotedMessage.found(msg('1'));

      expect(unknown.isFound, isFalse);
      expect(unknown.deleted, isFalse);
      expect(deleted.isFound, isFalse);
      expect(deleted.deleted, isTrue);
      expect(found.isFound, isTrue);
      expect(found.deleted, isFalse);
      expect(found.message!.id, '1');
    });
  });

  group('QuotedMessage.settle', () {
    Future<ChatMessage?> opens(Map<String, dynamic> row) async =>
        msg(row['id'] as String);
    Future<ChatMessage?> refuses(Map<String, dynamic> _) async => null;

    test('a failed request claims nothing', () async {
      final q = await QuotedMessage.settle(
        APIResponse.error('offline'),
        stillOpen: () => true,
        open: opens,
      );
      expect(q.isFound, isFalse);
      expect(q.deleted, isFalse);
    });

    test('an answer about a conversation since left claims nothing', () async {
      final q = await QuotedMessage.settle(
        APIResponse.success({
          'message': {'id': '1'},
        }),
        stillOpen: () => false,
        open: opens,
      );
      expect(q.isFound, isFalse);
      expect(q.deleted, isFalse);
    });

    test('no row is a deletion', () async {
      final q = await QuotedMessage.settle(
        APIResponse.success({'message': null}),
        stillOpen: () => true,
        open: opens,
      );
      expect(q.deleted, isTrue);
    });

    test('a row that does not open is unknown, not deleted', () async {
      final q = await QuotedMessage.settle(
        APIResponse.success({
          'message': {'id': '1'},
        }),
        stillOpen: () => true,
        open: refuses,
      );
      expect(q.isFound, isFalse);
      expect(q.deleted, isFalse);
    });

    test('a row that opens is found', () async {
      final q = await QuotedMessage.settle(
        APIResponse.success({
          'message': {'id': '7'},
        }),
        stillOpen: () => true,
        open: opens,
      );
      expect(q.message!.id, '7');
    });
  });

  group('QuotedMessage.settleMany', () {
    test('found, deleted and unknown, each by its own id', () async {
      // 1 opens, 2 has no row, 3 comes back and does not verify.
      final answers = await QuotedMessage.settleMany(
        APIResponse.success({
          'messages': [
            {'id': 1},
            {'id': 3},
          ],
        }),
        ids: ['1', '2', '3'],
        stillOpen: () => true,
        open: (rows) async => [
          for (final r in rows)
            if (r['id'] == 1) msg('1'),
        ],
      );
      expect(answers['1']!.isFound, isTrue);
      expect(answers['2']!.deleted, isTrue);
      expect(answers['3']!.isFound, isFalse);
      expect(answers['3']!.deleted, isFalse);
    });

    test('a failed read claims nothing about any of them', () async {
      final answers = await QuotedMessage.settleMany(
        APIResponse.error('offline'),
        ids: ['1', '2'],
        stillOpen: () => true,
        open: (_) async => [],
      );
      expect(answers.values.any((q) => q.isFound || q.deleted), isFalse);
    });
  });

  group('QuoteBatcher', () {
    test('one frame\'s lookups are one read per conversation', () async {
      final reads = <String>[];
      final batcher = QuoteBatcher<String>((key, ids) async {
        reads.add('$key: ${ids.join(',')}');
        return {for (final id in ids) id: QuotedMessage.found(msg(id))};
      });
      final answers = await Future.wait([
        batcher.lookUp('c1', '1'),
        batcher.lookUp('c1', '2'),
        batcher.lookUp('c1', '1'),
        batcher.lookUp('c2', '9'),
      ]);
      expect(reads, ['c1: 1,2', 'c2: 9']);
      expect(answers.map((q) => q.message!.id), ['1', '2', '1', '9']);

      // A later frame is a read of its own.
      await batcher.lookUp('c1', '3');
      expect(reads.last, 'c1: 3');
    });

    test('a big frame is read in chunks', () async {
      final sizes = <int>[];
      final batcher = QuoteBatcher<String>((key, ids) async {
        sizes.add(ids.length);
        return {};
      }, chunk: 2);
      await Future.wait([
        for (var i = 0; i < 5; i++) batcher.lookUp('c', '$i'),
      ]);
      expect(sizes, [2, 2, 1]);
    });

    test('a read that throws, or leaves an id out, is unknown', () async {
      final batcher = QuoteBatcher<String>((key, ids) async {
        if (key == 'bad') throw StateError('offline');
        return {};
      });
      final (thrown, missing) = await (
        batcher.lookUp('bad', '1'),
        batcher.lookUp('ok', '2'),
      ).wait;
      expect(thrown.isFound || thrown.deleted, isFalse);
      expect(missing.isFound || missing.deleted, isFalse);
    });
  });
}
