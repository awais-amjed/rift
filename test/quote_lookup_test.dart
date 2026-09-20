import 'package:flutter_test/flutter_test.dart';
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
}
