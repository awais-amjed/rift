import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_body.dart';
import 'package:rift/logic/services/message_excerpt.dart';

/// Replying to a message: the reference that rides inside the sealed body,
/// what a reply is allowed to say about what it answers, and the grouping
/// rule that keeps the quote attached to the right row.
void main() {
  Attachment att(AttachmentKind kind, {String name = 'f'}) => Attachment(
    id: name,
    kind: kind,
    name: name,
    mime: 'application/octet-stream',
    size: 1,
    storagePath: 'c/$name.bin',
    keyB64: 'k',
    nonceB64: 'n',
  );

  ChatMessage msg({
    String id = '1',
    String text = 'hello',
    String author = 'ana',
    List<Attachment> attachments = const [],
    bool isLocked = false,
    String? replyToId,
  }) => ChatMessage(
    id: id,
    authorId: author,
    authorName: author,
    text: text,
    attachments: attachments,
    isLocked: isLocked,
    replyToId: replyToId,
    sentAt: DateTime.utc(2026, 9, 20),
    isMine: false,
  );

  group('MessageBody carries the reference', () {
    test('round-trips through the sealed plaintext', () {
      final back = MessageBody.decode(
        const MessageBody(text: 'yes', replyToId: '412').encode(),
      );
      expect(back.replyToId, '412');
      expect(back.text, 'yes');
    });

    test('an ordinary message encodes no reply field at all', () {
      expect(const MessageBody(text: 'hi').encode(), isNot(contains('"re"')));
      expect(
        MessageBody.decode('{"t":"rift.msg","v":1,"text":"hi"}').replyToId,
        isNull,
      );
    });

    test('the body never carries a copy of what it answers', () {
      // The whole reason the field is an id. If a quote ever rides along,
      // it is text the *replier* wrote being drawn under somebody else's
      // name, and this assertion is the one that should stop it.
      final encoded = const MessageBody(text: 'ok', replyToId: '7').encode();
      expect(encoded, contains('"re":"7"'));
      expect(encoded.length, lessThan(80));
    });

    test('a junk reference is no reference', () {
      // The sender controls this field. An empty string would resolve to
      // nothing while still drawing the "original unavailable" bar, which
      // says a reply was lost when none was made.
      for (final raw in ['""', '123', 'null', '{"id":"4"}', '["4"]']) {
        final body = MessageBody.decode(
          '{"t":"rift.msg","v":1,"text":"x","re":$raw}',
        );
        expect(body.replyToId, isNull, reason: raw);
        expect(body.text, 'x', reason: raw);
      }
    });

    test('a legacy plain-text body is not a reply', () {
      expect(MessageBody.decode('just text').replyToId, isNull);
    });
  });

  group('grouping', () {
    test('a reply starts its own group', () {
      // Otherwise it tucks under the message above it as a continuation and
      // loses its header — and the quote is drawn once, on the header row.
      expect(msg(replyToId: '9').groupKey, isNot(msg().groupKey));
    });

    test('two replies to the same message still group', () {
      expect(
        msg(id: '2', replyToId: '9').groupKey,
        msg(id: '3', replyToId: '9').groupKey,
      );
    });

    test('replies to different messages do not', () {
      expect(
        msg(id: '2', replyToId: '9').groupKey,
        isNot(msg(id: '3', replyToId: '10').groupKey),
      );
    });

    test('copyWith keeps the reference', () {
      // Editing re-seals the body from scratch; a copyWith that dropped this
      // would take the thread apart on a typo fix.
      expect(msg(replyToId: '9').copyWith(text: 'fixed').replyToId, '9');
    });
  });

  group('MessageExcerpt', () {
    test('collapses a message to one line', () {
      expect(MessageExcerpt.of(msg(text: 'a\n\nb   c')), 'a b c');
    });

    test('clips a long one and marks that it did', () {
      final long = MessageExcerpt.of(msg(text: 'x' * 400));
      expect(long.length, lessThanOrEqualTo(MessageExcerpt.maxLength + 1));
      expect(long, endsWith('…'));
    });

    test('a locked message quotes as locked, never as nothing', () {
      // Its text is empty because the key has not arrived, and "Message" in
      // the one place a reader looks for context would say there was none.
      expect(
        MessageExcerpt.of(msg(text: '', isLocked: true)),
        'Message you cannot open yet',
      );
    });

    test('names what a wordless message carried', () {
      expect(
        MessageExcerpt.of(
          msg(text: '', attachments: [att(AttachmentKind.image)]),
        ),
        'Image',
      );
      expect(
        MessageExcerpt.of(
          msg(
            text: '',
            attachments: [
              att(AttachmentKind.image, name: 'a'),
              att(AttachmentKind.image, name: 'b'),
            ],
          ),
        ),
        'Images',
      );
      expect(
        MessageExcerpt.of(
          msg(
            text: '',
            attachments: [
              att(AttachmentKind.image, name: 'a'),
              att(AttachmentKind.file, name: 'b'),
            ],
          ),
        ),
        'Attachments',
      );
      expect(
        MessageExcerpt.of(
          msg(text: '', attachments: [att(AttachmentKind.audio)]),
        ),
        'Voice message',
      );
    });

    test('text wins over attachments', () {
      expect(
        MessageExcerpt.of(
          msg(text: 'look', attachments: [att(AttachmentKind.image)]),
        ),
        'look',
      );
    });

    test('a message with nothing in it still says something', () {
      expect(MessageExcerpt.of(msg(text: '')), 'Message');
    });
  });
}
