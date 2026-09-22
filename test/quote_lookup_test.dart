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
}
