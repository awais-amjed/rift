import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/pending_attachment.dart';
import 'package:rift/logic/services/chat_attachment_uploader.dart';
import 'package:rift/logic/services/link_preview_fetcher.dart';
import 'package:rift/logic/services/media_store.dart';

/// The upload step all three chat pipelines share. What matters most is the
/// failure: its code is what decides between the outbox and a refusal.
void main() {
  setUp(MediaStore.attachments.clear);

  PendingAttachment file(String name, List<int> bytes) => PendingAttachment(
    bytes: Uint8List.fromList(bytes),
    name: name,
    mime: 'image/png',
    kind: AttachmentKind.image,
    width: 4,
    height: 3,
  );

  APIResponse stored(String path) => APIResponse.success((
    path: path,
    keyB64: 'k-$path',
    nonceB64: 'n-$path',
    sha256B64: null,
    chunkSize: null,
  ));

  group('uploadAll', () {
    test('uploads in order and keeps each file\'s metadata', () async {
      var n = 0;
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.png', [1]),
          file('b.png', [2, 2]),
        ],
        uploadOne: (_, {onProgress}) async => stored('p${n++}'),
      );

      expect(result.map((a) => a.storagePath), ['p0', 'p1']);
      expect(result.map((a) => a.name), ['a.png', 'b.png']);
      expect(result[1].size, 2);
      expect(result[0].keyB64, 'k-p0');
      expect(result[0].width, 4);
      expect(result[0].id, isNot(result[1].id));
    });

    // The sender's choice reaches the upload, and the digest the upload
    // answers with reaches the attachment, which is what marks it plain.
    test('a file chosen to go unencrypted goes up plain', () async {
      final asked = <bool>[];
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.bin', [1]).copyWith(plain: true),
          file('b.bin', [2]),
        ],
        uploadOne: (file, {onProgress}) async {
          asked.add(file.plain);
          return file.plain
              ? APIResponse.success((
                  path: 'p',
                  keyB64: '',
                  nonceB64: '',
                  sha256B64: 'digest',
                  chunkSize: null,
                ))
              : stored('q');
        },
      );
      expect(asked, [true, false]);
      expect(result[0].isEncrypted, isFalse);
      expect(result[0].sha256B64, 'digest');
      expect(result[1].isEncrypted, isTrue);
    });

    // Progress is over all the files together, by size, and only reported
    // when it has moved by a percent: the chat list redraws on every report.
    test('reports progress over every file, in percent steps', () async {
      final heard = <double>[];
      await ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.bin', List.filled(300, 1)),
          file('b.bin', List.filled(100, 2)),
        ],
        uploadOne: (file, {onProgress}) async {
          // A sealed file is a little bigger on the wire than on disk.
          final wire = file.size + 16;
          for (var done = 0; done <= wire; done += 1) {
            onProgress?.call(done, wire);
          }
          return stored(file.name);
        },
        onProgress: heard.add,
      );
      expect(heard.first, greaterThan(0));
      expect(heard.last, 1.0);
      for (var i = 1; i < heard.length; i++) {
        expect(heard[i], greaterThanOrEqualTo(heard[i - 1]));
        if (heard[i] < 1) {
          expect(heard[i] - heard[i - 1], greaterThanOrEqualTo(0.01));
        }
      }
      expect(heard.length, lessThan(120));
    });

    test('puts the sender\'s own bytes in the cache', () async {
      await ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.png', [7, 8]),
        ],
        uploadOne: (_, {onProgress}) async => stored('p'),
      );
      expect(MediaStore.attachments['p']?.bytes, [7, 8]);
    });

    test('stops at the first failure and carries its code', () async {
      var calls = 0;
      final upload = ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.png', [1]),
          file('b.png', [2]),
        ],
        uploadOne: (_, {onProgress}) async {
          calls++;
          return APIResponse.error('offline', errorCode: 'network');
        },
      );

      await expectLater(
        upload,
        throwsA(
          isA<AttachmentUploadException>()
              .having((e) => e.errorCode, 'errorCode', 'network')
              .having((e) => e.message, 'message', 'offline'),
        ),
      );
      expect(calls, 1);
    });

    test('a success with no data is a failure', () async {
      await expectLater(
        ChatAttachmentUploader.uploadAll(
          pending: [
            file('a.png', [1]),
          ],
          uploadOne: (_, {onProgress}) async => APIResponse(success: true),
        ),
        throwsA(isA<AttachmentUploadException>()),
      );
    });
  });

  group('posters', () {
    PendingAttachment video({Uint8List? poster}) => PendingAttachment(
      bytes: Uint8List.fromList([9, 9, 9]),
      name: 'clip.mp4',
      mime: 'video/mp4',
      kind: AttachmentKind.video,
      width: 1920,
      height: 1080,
      poster: poster,
    );
    final jpeg = Uint8List.fromList([0xff, 0xd8, 1, 2]);

    test('a video goes up, then its poster, the same way', () async {
      final sent = <PendingAttachment>[];
      var n = 0;
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [video()],
        uploadOne: (f, {onProgress}) async {
          sent.add(f);
          return stored('p${n++}');
        },
        posterOf: (_) async => jpeg,
      );

      expect(sent.map((f) => f.name), ['clip.mp4', 'poster.jpg']);
      final poster = result.single.poster!;
      expect(poster.storagePath, 'p1');
      expect(poster.kind, AttachmentKind.image);
      expect(poster.mime, 'image/jpeg');
      expect(poster.size, jpeg.length);
      expect(poster.keyB64, 'k-p1');
      // The sender's card draws it without fetching it back.
      expect(MediaStore.attachments['p1']?.bytes, jpeg);
    });

    test('a picture or a sound gets no poster', () async {
      var asked = 0;
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [
          file('a.png', [1]),
        ],
        uploadOne: (_, {onProgress}) async => stored('p'),
        posterOf: (_) async {
          asked++;
          return jpeg;
        },
      );
      expect(asked, 0);
      expect(result.single.poster, isNull);
    });

    test('one that cannot be made sends the video without', () async {
      var uploads = 0;
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [video()],
        uploadOne: (_, {onProgress}) async => stored('p${uploads++}'),
        posterOf: (_) async => null,
      );
      expect(uploads, 1);
      expect(result.single.poster, isNull);
    });

    test('one that will not make or upload never fails the send', () async {
      final thrown = await ChatAttachmentUploader.uploadAll(
        pending: [video()],
        uploadOne: (_, {onProgress}) async => stored('p'),
        posterOf: (_) async => throw StateError('no decoder'),
      );
      expect(thrown.single.storagePath, 'p');
      expect(thrown.single.poster, isNull);

      var n = 0;
      final refused = await ChatAttachmentUploader.uploadAll(
        pending: [video()],
        uploadOne: (_, {onProgress}) async =>
            n++ == 0 ? stored('v') : APIResponse.error('full'),
        posterOf: (_) async => jpeg,
      );
      expect(refused.single.storagePath, 'v');
      expect(refused.single.poster, isNull);
    });

    test('a forwarded video sends the poster it came with', () async {
      var made = 0;
      final result = await ChatAttachmentUploader.uploadAll(
        pending: [video(poster: jpeg)],
        uploadOne: (_, {onProgress}) async => stored('p'),
        posterOf: (_) async {
          made++;
          return Uint8List(1);
        },
      );
      expect(made, 0);
      expect(result.single.poster!.size, jpeg.length);
    });
  });

  group('uploadPreview', () {
    test('no preview uploads nothing', () async {
      final preview = await ChatAttachmentUploader.uploadPreview(
        preview: null,
        uploadOne: (_, {onProgress}) async => fail('should not upload'),
      );
      expect(preview, isNull);
    });

    test('a preview without a picture keeps its words', () async {
      final preview = await ChatAttachmentUploader.uploadPreview(
        preview: Future.value(
          const PendingLinkPreview(url: 'https://a.b', title: 'T'),
        ),
        uploadOne: (_, {onProgress}) async => fail('should not upload'),
      );
      expect(preview!.title, 'T');
      expect(preview.image, isNull);
    });

    test('the thumbnail takes the attachment road', () async {
      final preview = await ChatAttachmentUploader.uploadPreview(
        preview: Future.value(
          PendingLinkPreview(url: 'https://a.b', image: file('t.png', [1])),
        ),
        uploadOne: (_, {onProgress}) async => stored('thumb'),
      );
      expect(preview!.image!.storagePath, 'thumb');
    });

    test('a preview still being fetched is waited for', () async {
      final fetch = Completer<PendingLinkPreview?>();
      final uploading = ChatAttachmentUploader.uploadPreview(
        preview: fetch.future,
        uploadOne: (_, {onProgress}) async => fail('should not upload'),
      );
      fetch.complete(const PendingLinkPreview(url: 'https://a.b', title: 'T'));
      expect((await uploading)!.title, 'T');
    });

    test('a fetch that found nothing sends the message bare', () async {
      final preview = await ChatAttachmentUploader.uploadPreview(
        preview: Future.value(null),
        uploadOne: (_, {onProgress}) async => fail('should not upload'),
      );
      expect(preview, isNull);
    });
  });

  group('load', () {
    Attachment at(String path) => Attachment(
      id: 'x',
      kind: AttachmentKind.file,
      name: 'f',
      mime: 'text/plain',
      size: 1,
      storagePath: path,
      keyB64: 'k',
      nonceB64: 'n',
    );

    test('reads the cache before the network', () async {
      MediaStore.attachments.put('p', Uint8List.fromList([9]));
      final bytes = await ChatAttachmentUploader.load(
        attachment: at('p'),
        download: () async => fail('should not download'),
      );
      expect(bytes, [9]);
    });

    test('caches what it downloads', () async {
      final bytes = await ChatAttachmentUploader.load(
        attachment: at('q'),
        download: () async => APIResponse.success(Uint8List.fromList([5])),
      );
      expect(bytes, [5]);
      expect(MediaStore.attachments['q']?.bytes, [5]);
    });

    test('a failed download is null and caches nothing', () async {
      final bytes = await ChatAttachmentUploader.load(
        attachment: at('r'),
        download: () async => APIResponse.error('gone'),
      );
      expect(bytes, isNull);
      expect(MediaStore.attachments['r']?.bytes, isNull);
    });
  });
}
