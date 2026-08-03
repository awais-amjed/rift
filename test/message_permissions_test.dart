import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/services/chat_message_ops.dart';
import 'package:rift/logic/services/message_permissions.dart';

ChatMessage msg({
  String id = '1',
  String text = 'hello',
  bool isMine = true,
  bool isPending = false,
  List<Attachment> attachments = const [],
  DateTime? editedAt,
}) => ChatMessage(
  id: id,
  authorId: isMine ? 'me' : 'them',
  authorName: isMine ? 'Me' : 'Them',
  text: text,
  sentAt: DateTime(2026, 8, 3),
  isMine: isMine,
  isPending: isPending,
  attachments: attachments,
  editedAt: editedAt,
);

void main() {
  group('MessagePermissions.canEdit', () {
    test('the author may edit their own text message', () {
      expect(MessagePermissions.canEdit(msg()), isTrue);
    });

    test('nobody may edit someone else’s message', () {
      expect(MessagePermissions.canEdit(msg(isMine: false)), isFalse);
    });

    test('a pending message is not editable yet', () {
      expect(MessagePermissions.canEdit(msg(isPending: true)), isFalse);
    });

    test('an attachment-only message has no text to edit', () {
      final attachmentOnly = msg(
        text: '',
        attachments: [
          const Attachment(
            id: 'a',
            kind: AttachmentKind.image,
            name: 'a.png',
            mime: 'image/png',
            size: 10,
            storagePath: 'p',
            keyB64: 'k',
            nonceB64: 'n',
          ),
        ],
      );
      expect(MessagePermissions.canEdit(attachmentOnly), isFalse);
    });
  });

  group('MessagePermissions.canDelete', () {
    test('the author may delete their own', () {
      expect(MessagePermissions.canDelete(msg(), isModerator: false), isTrue);
    });

    test('a moderator may delete someone else’s', () {
      expect(
        MessagePermissions.canDelete(msg(isMine: false), isModerator: true),
        isTrue,
      );
    });

    test('a non-moderator may not delete someone else’s', () {
      expect(
        MessagePermissions.canDelete(msg(isMine: false), isModerator: false),
        isFalse,
      );
    });

    test('a pending message cannot be deleted, even by a moderator', () {
      expect(
        MessagePermissions.canDelete(msg(isPending: true), isModerator: true),
        isFalse,
      );
    });

    test('a moderator may still delete their own', () {
      expect(MessagePermissions.canDelete(msg(), isModerator: true), isTrue);
    });
  });

  group('ChatMessageOps edit/delete transforms', () {
    final list = [msg(id: '1'), msg(id: '2', text: 'two'), msg(id: '3')];

    test('applyEdit swaps the text and stamps editedAt on one row only', () {
      final at = DateTime(2026, 8, 3, 12);
      final out = ChatMessageOps.applyEdit(
        list,
        messageId: '2',
        text: 'edited',
        editedAt: at,
      );
      expect(out[1].text, 'edited');
      expect(out[1].editedAt, at);
      expect(out[1].isEdited, isTrue);
      expect(out[0].text, 'hello');
      expect(out[0].isEdited, isFalse);
      expect(out.length, 3);
    });

    test('applyEdit on an unknown id changes nothing', () {
      final out = ChatMessageOps.applyEdit(
        list,
        messageId: 'nope',
        text: 'x',
        editedAt: DateTime(2026),
      );
      expect(out.map((m) => m.text), list.map((m) => m.text));
    });

    test('applyEdit keeps attachments and reactions', () {
      final withAttachment = [
        msg(
          id: '9',
          attachments: [
            const Attachment(
              id: 'a',
              kind: AttachmentKind.image,
              name: 'a.png',
              mime: 'image/png',
              size: 10,
              storagePath: 'p',
              keyB64: 'k',
              nonceB64: 'n',
            ),
          ],
        ),
      ];
      final out = ChatMessageOps.applyEdit(
        withAttachment,
        messageId: '9',
        text: 'new',
        editedAt: DateTime(2026),
      );
      expect(out.single.attachments, hasLength(1));
      expect(out.single.text, 'new');
    });

    test('removeMessage drops exactly the one row', () {
      final out = ChatMessageOps.removeMessage(list, '2');
      expect(out.map((m) => m.id), ['1', '3']);
    });

    test('removeMessage on an unknown id is a no-op', () {
      expect(ChatMessageOps.removeMessage(list, 'nope'), hasLength(3));
    });
  });
}
