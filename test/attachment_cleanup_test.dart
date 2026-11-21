import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/forwarded_message.dart';
import 'package:rift/data/classes/link_preview.dart';
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

const _origin = 'https://s.invalid#server';

/// What [path]'s bytes are held under, as [_attachment] makes it.
String _key(String path) =>
    MediaStore.attachmentKey(_origin, _attachment(path));

ChatMessage _message({
  List<Attachment> attachments = const [],
  bool isMine = true,
  ForwardedMessage? forwarded,
  LinkPreview? preview,
}) => ChatMessage(
  id: '1',
  authorId: 'u1',
  authorName: 'Sam',
  text: 'hi',
  attachments: attachments,
  forwarded: forwarded,
  preview: preview,
  sentAt: DateTime(2026, 8, 12),
  isMine: isMine,
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

    test("a video's poster goes with it", () {
      final video = Attachment(
        id: 'v',
        kind: AttachmentKind.video,
        name: 'clip.mp4',
        mime: 'video/mp4',
        size: 10,
        storagePath: 'c1/v.bin',
        keyB64: 'k',
        nonceB64: 'n',
        poster: _attachment('c1/p.bin'),
      );
      expect(AttachmentCleanup.pathsOf(_message(attachments: [video])), [
        'c1/v.bin',
        'c1/p.bin',
      ]);
    });
  });

  test("a forward's copies and a link card's picture go too", () {
    final message = _message(
      attachments: [_attachment('c1/a.bin')],
      forwarded: ForwardedMessage(attachments: [_attachment('c1/f.bin')]),
      preview: LinkPreview(
        url: 'https://example.com/',
        image: _attachment('c1/card.bin'),
      ),
    );
    expect(AttachmentCleanup.pathsOf(message), [
      'c1/a.bin',
      'c1/f.bin',
      'c1/card.bin',
    ]);
  });

  group('AttachmentCleanup.forMessage', () {
    // The paths are in a body its sender wrote: a manager deleting someone
    // else's message must not delete whatever files it names (review, Nov 22).
    test(
      "another's message deletes nothing but lets go of its bytes",
      () async {
        MediaStore.attachments.put(_key('c1/a.bin'), Uint8List.fromList([1]));
        var called = false;
        await AttachmentCleanup.forMessage(
          _message(attachments: [_attachment('c1/a.bin')], isMine: false),
          origin: _origin,
          delete: (_) async {
            called = true;
            return APIResponse.success(null);
          },
        );
        expect(called, isFalse);
        expect(MediaStore.attachments[_key('c1/a.bin')] != null, isFalse);
      },
    );

    test('asks for exactly the message\'s blobs', () async {
      List<String>? asked;
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        origin: _origin,
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
        origin: _origin,
        delete: (_) async {
          called = true;
          return APIResponse.success(null);
        },
      );
      expect(called, isFalse);
    });

    test('drops the decrypted bytes from the cache', () async {
      MediaStore.attachments.put(
        _key('c1/a.bin'),
        Uint8List.fromList([1, 2, 3]),
      );
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        origin: _origin,
        delete: (_) async => APIResponse.success(null),
      );
      expect(MediaStore.attachments[_key('c1/a.bin')] != null, isFalse);
    });

    test('still drops the bytes when the delete fails', () async {
      // The message is gone from the screen either way, so its plaintext must
      // not survive in memory just because the network did not cooperate.
      MediaStore.attachments.put(
        _key('c1/a.bin'),
        Uint8List.fromList([1, 2, 3]),
      );
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        origin: _origin,
        delete: (_) async => APIResponse.error('nope'),
      );
      expect(MediaStore.attachments[_key('c1/a.bin')] != null, isFalse);
    });

    test('a failed delete does not throw — the sweep collects it later', () {
      expect(
        AttachmentCleanup.forMessage(
          _message(attachments: [_attachment('c1/a.bin')]),
          origin: _origin,
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
          origin: _origin,
          delete: (_) async => throw Exception('offline'),
        ),
        completes,
      );
    });

    test('leaves other cached attachments alone', () async {
      MediaStore.attachments.put(_key('c1/a.bin'), Uint8List.fromList([1]));
      MediaStore.attachments.put(_key('c1/keep.bin'), Uint8List.fromList([2]));
      await AttachmentCleanup.forMessage(
        _message(attachments: [_attachment('c1/a.bin')]),
        origin: _origin,
        delete: (_) async => APIResponse.success(null),
      );
      expect(MediaStore.attachments[_key('c1/keep.bin')] != null, isTrue);
    });
  });
}
