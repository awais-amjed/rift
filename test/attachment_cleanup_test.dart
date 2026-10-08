import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/services/attachment_cleanup.dart';
import 'package:rift/logic/services/media_store.dart';

Attachment _attachment(String path) => Attachment(
  id: path,
  kind: AttachmentKind.image,
  name: 'photo.png',
  mime: 'image/png',
  size: 10,
  storagePath: path,
  keyB64: 'k',
  nonceB64: 'n',
);

ChatMessage _message({List<Attachment> attachments = const []}) => ChatMessage(
  id: '1',
  authorId: 'u1',
  authorName: 'Sam',
  text: 'hi',
  attachments: attachments,
  sentAt: DateTime(2026, 8, 12),
  isMine: true,
);

void main() {
  setUp(MediaStore.attachments.clear);

  group('AttachmentCleanup.pathsOf', () {
    test('a plain text message has nothing to clean up', () {
      expect(AttachmentCleanup.pathsOf(_message()), isEmpty);
    });

    test('a message we no longer hold is not an error', () {
      // deleteMessage captures the row before removing it, but a doorbell or a
      // race can leave that null. It must read as "nothing to do".
      expect(AttachmentCleanup.pathsOf(null), isEmpty);
    });

    test('every attachment path, in order', () {
      final message = _message(
        attachments: [_attachment('c1/a.bin'), _attachment('c1/b.bin')],
      );
      expect(AttachmentCleanup.pathsOf(message), ['c1/a.bin', 'c1/b.bin']);
    });
  });

  group('AttachmentCleanup.forMessage', () {
    test('asks for exactly the message\'s blobs', () async {
      List<String>? asked;
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        delete: (paths) async {
          asked = paths;
          return APIResponse.success(null);
        },
      );
      expect(asked, ['c1/a.bin']);
    });

    test('a message with no attachments makes no call at all', () async {
      var called = false;
      await AttachmentCleanup.forMessage(
        _message(),
        delete: (_) async {
          called = true;
          return APIResponse.success(null);
        },
      );
      expect(called, isFalse);
    });

    test('drops the decrypted bytes from the cache', () async {
      MediaStore.attachments.put('c1/a.bin', Uint8List.fromList([1, 2, 3]));
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        delete: (_) async => APIResponse.success(null),
      );
      expect(MediaStore.attachments['c1/a.bin'] != null, isFalse);
    });

    test('still drops the bytes when the delete fails', () async {
      // The message is gone from the screen either way, so its plaintext must
      // not survive in memory just because the network did not cooperate.
      MediaStore.attachments.put('c1/a.bin', Uint8List.fromList([1, 2, 3]));
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        delete: (_) async => APIResponse.error('nope'),
      );
      expect(MediaStore.attachments['c1/a.bin'] != null, isFalse);
    });

    test('a failed delete does not throw — the sweep collects it later', () {
      expect(
        AttachmentCleanup.forMessage(
          _message(attachments: [_attachment('c1/a.bin')]),
          delete: (_) async => APIResponse.error('nope'),
        ),
        completes,
      );
    });

    test('a delete that throws does not escape either', () {
      // A blob must never be able to fail the message delete around it.
      expect(
        AttachmentCleanup.forMessage(
          _message(attachments: [_attachment('c1/a.bin')]),
          delete: (_) async => throw Exception('offline'),
        ),
        completes,
      );
    });

    test('leaves other cached attachments alone', () async {
      MediaStore.attachments.put('c1/a.bin', Uint8List.fromList([1]));
      MediaStore.attachments.put('c1/keep.bin', Uint8List.fromList([2]));
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        delete: (_) async => APIResponse.success(null),
      );
      expect(MediaStore.attachments['c1/keep.bin'] != null, isTrue);
    });
  });
}
