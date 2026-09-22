import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/forwarded_message.dart';
import 'package:rift/data/classes/message_body.dart';

void main() {
  Attachment sampleAttachment() => const Attachment(
    id: 'a1',
    kind: AttachmentKind.image,
    name: 'cat.png',
    mime: 'image/png',
    size: 1234,
    storagePath: 'chan-1/deadbeef.bin',
    keyB64: 'a2V5',
    nonceB64: 'bm9uY2U=',
    width: 640,
    height: 480,
  );

  group('MessageBody encode/decode', () {
    test('round-trips text + attachments', () {
      final body = MessageBody(
        text: 'look 👀',
        attachments: [sampleAttachment()],
      );
      final decoded = MessageBody.decode(body.encode());

      expect(decoded.text, 'look 👀');
      expect(decoded.attachments, hasLength(1));
      final a = decoded.attachments.single;
      expect(a.name, 'cat.png');
      expect(a.kind, AttachmentKind.image);
      expect(a.storagePath, 'chan-1/deadbeef.bin');
      expect(a.keyB64, 'a2V5');
      expect(a.width, 640);
      expect(a.height, 480);
    });

    test('a text-only body encodes without an attachments array', () {
      final decoded = MessageBody.decode(
        const MessageBody(text: 'hi').encode(),
      );
      expect(decoded.text, 'hi');
      expect(decoded.attachments, isEmpty);
    });

    test('legacy plain-text plaintext decodes to a text-only body '
        '(backward compatibility)', () {
      final decoded = MessageBody.decode('just a normal old message');
      expect(decoded.text, 'just a normal old message');
      expect(decoded.attachments, isEmpty);
    });

    test('arbitrary JSON that is not our tagged body is treated as text', () {
      // A user could legitimately type valid JSON as a message.
      const raw = '{"hello": "world"}';
      final decoded = MessageBody.decode(raw);
      expect(decoded.text, raw);
      expect(decoded.attachments, isEmpty);
    });

    test('isEmpty reflects both text and attachments', () {
      expect(const MessageBody().isEmpty, isTrue);
      expect(const MessageBody(text: '   ').isEmpty, isTrue);
      expect(const MessageBody(text: 'x').isEmpty, isFalse);
      expect(MessageBody(attachments: [sampleAttachment()]).isEmpty, isFalse);
    });
  });

  group('MessageBody.edited', () {
    test('changes the words and carries everything else through', () {
      // An edit re-seals the whole body; whatever is not carried is lost.
      final existing = ChatMessage(
        id: '1',
        authorId: 'a',
        authorName: 'a',
        text: 'old',
        sentAt: DateTime.utc(2026, 9, 22),
        isMine: true,
        attachments: [sampleAttachment()],
        replyToId: '9',
        forwarded: const ForwardedMessage(text: 'quoted'),
      );
      final body = MessageBody.edited(existing, 'new');
      expect(body.text, 'new');
      expect(body.attachments, hasLength(1));
      expect(body.replyToId, '9');
      expect(body.forwarded!.text, 'quoted');
    });
  });

  group('Attachment', () {
    test('JSON round-trips (including optional media hints)', () {
      final back = Attachment.fromJson(sampleAttachment().toJson());
      expect(back.id, 'a1');
      expect(back.kind, AttachmentKind.image);
      expect(back.size, 1234);
      expect(back.durationMs, isNull);
    });

    test('kind is inferred from mime', () {
      expect(AttachmentKind.fromMime('image/webp'), AttachmentKind.image);
      expect(AttachmentKind.fromMime('audio/ogg'), AttachmentKind.audio);
      expect(AttachmentKind.fromMime('application/pdf'), AttachmentKind.file);
    });
  });
}
