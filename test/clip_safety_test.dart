import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/enums/sensitive_content_mode.dart';
import 'package:rift/logic/services/image_safety.dart';
import 'package:rift/logic/services/image_safety_classifier.dart';
import 'package:rift/presentation/common/chat/attachments/sensitive_image_cover.dart';
import 'package:rift/presentation/common/chat/attachments/video/clip_safety.dart';

/// A chat video's cover follows the verdicts kept for it and its poster:
/// covered at once when either was flagged, never with the setting off, and
/// lifted for the session once pressed.
void main() {
  setUp(SensitiveImageCover.resetReveals);

  const flagged = ImageSafetyVerdict(safe: 0.1, sexual: 0.8, gore: 0.1);
  const fine = ImageSafetyVerdict(safe: 0.95, sexual: 0.03, gore: 0.02);

  Attachment video(String id) => Attachment(
    id: id,
    kind: AttachmentKind.video,
    name: 'clip.mp4',
    mime: 'video/mp4',
    size: 1,
    storagePath: 'p/$id',
    keyB64: '',
    nonceB64: '',
    poster: Attachment(
      id: '$id-poster',
      kind: AttachmentKind.image,
      name: 'poster.jpg',
      mime: 'image/jpeg',
      size: 1,
      storagePath: 'p/$id-poster',
      keyB64: '',
      nonceB64: '',
    ),
  );

  ClipSafety safety(Attachment a, SensitiveContentMode mode) =>
      ClipSafety(attachment: a, mode: mode, changed: () {}, flagged: () {});

  test('a video flagged before is covered at once', () {
    final a = video('v-known');
    ImageSafetyClassifier.instance.remember(a.id, flagged);
    expect(safety(a, SensitiveContentMode.blur).covered, isTrue);
    expect(safety(a, SensitiveContentMode.hide).covered, isTrue);
    expect(safety(a, SensitiveContentMode.off).covered, isFalse);
  });

  test('a flagged poster covers the video and is kept for it', () {
    final a = video('v-poster');
    ImageSafetyClassifier.instance.remember(a.poster!.id, flagged);
    final s = safety(a, SensitiveContentMode.blur);
    expect(s.covered, isFalse);
    expect(s.posterChecked, isFalse);

    s.lookAtPoster(Uint8List(1));
    expect(s.posterChecked, isTrue);
    expect(s.covered, isTrue);
    // A card made again for it, after a scroll, is covered before any look.
    expect(safety(a, SensitiveContentMode.blur).covered, isTrue);
  });

  test('a fine poster is drawn and leaves it uncovered', () {
    final a = video('v-fine');
    ImageSafetyClassifier.instance.remember(a.poster!.id, fine);
    final s = safety(a, SensitiveContentMode.blur)..lookAtPoster(Uint8List(1));
    expect(s.posterChecked, isTrue);
    expect(s.covered, isFalse);
  });

  test('with the setting off the poster is drawn without a look', () {
    final a = video('v-off');
    final s = safety(a, SensitiveContentMode.off)..lookAtPoster(Uint8List(1));
    expect(s.posterChecked, isTrue);
    expect(ImageSafetyClassifier.instance.cached(a.poster!.id), isNull);
  });
}
