import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/logic/services/attachment_staging.dart';
import 'package:rift/logic/services/chat_clip/chat_clip.dart';
import 'package:rift/presentation/common/chat/attachments/message_attachments.dart';

Attachment _of(AttachmentKind kind, int size) => Attachment(
  id: 'a',
  kind: kind,
  name: 'f',
  mime: 'application/octet-stream',
  size: size,
  storagePath: 's/a.bin',
  keyB64: 'k',
  nonceB64: 'n',
);

/// A picture is read whole the moment it is seen, and a sound when it is
/// played, so one bigger than a file sent in one piece is a file to save
/// instead (review, Nov 22).
void main() {
  test('a picture past what is held in memory is a file', () {
    const max = AttachmentStaging.inMemoryMaxBytes;
    expect(
      MessageAttachments.drawnAs(_of(AttachmentKind.image, max)),
      AttachmentKind.image,
    );
    expect(
      MessageAttachments.drawnAs(_of(AttachmentKind.image, max + 1)),
      AttachmentKind.file,
    );
  });

  test('a sound past what plays from memory is a file', () {
    const max = ChatClip.wholeMaxBytes;
    expect(
      MessageAttachments.drawnAs(_of(AttachmentKind.audio, max)),
      AttachmentKind.audio,
    );
    expect(
      MessageAttachments.drawnAs(_of(AttachmentKind.audio, max + 1)),
      AttachmentKind.file,
    );
  });

  test('a video keeps its card at any size', () {
    expect(
      MessageAttachments.drawnAs(_of(AttachmentKind.video, 1 << 32)),
      AttachmentKind.video,
    );
  });
}
