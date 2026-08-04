import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/chat/attachments/attachment_image_thumb.dart';

/// The box a thumbnail reserves before its bytes arrive. Getting this wrong
/// is what made the message list jump: the placeholder and the decoded image
/// have to occupy exactly the same space.
void main() {
  const max = AttachmentImageThumb.maxSize;

  group('AttachmentImageThumb.boxFor', () {
    test('is unknown without dimensions, so the thumb sizes itself', () {
      expect(AttachmentImageThumb.boxFor(null, null), isNull);
      expect(AttachmentImageThumb.boxFor(800, null), isNull);
      expect(AttachmentImageThumb.boxFor(null, 600), isNull);
    });

    test(
      'treats nonsense dimensions as unknown rather than dividing by them',
      () {
        expect(AttachmentImageThumb.boxFor(0, 100), isNull);
        expect(AttachmentImageThumb.boxFor(100, 0), isNull);
        expect(AttachmentImageThumb.boxFor(-10, 100), isNull);
      },
    );

    test('a landscape image is capped on its width', () {
      final box = AttachmentImageThumb.boxFor(800, 400)!;
      expect(box.width, max);
      expect(box.height, max / 2);
    });

    test('a portrait image is capped on its height', () {
      final box = AttachmentImageThumb.boxFor(400, 800)!;
      expect(box.height, max);
      expect(box.width, max / 2);
    });

    test('aspect ratio survives the scaling', () {
      final box = AttachmentImageThumb.boxFor(1920, 1080)!;
      expect(box.width / box.height, closeTo(1920 / 1080, 0.001));
    });

    test('a small image keeps its own size rather than being blown up', () {
      final box = AttachmentImageThumb.boxFor(48, 48)!;
      expect(box.width, 48);
      expect(box.height, 48);
    });

    test('nothing ever exceeds the ceiling on either edge', () {
      for (final (w, h) in [(4000, 30), (30, 4000), (221, 221), (219, 500)]) {
        final box = AttachmentImageThumb.boxFor(w, h)!;
        expect(box.width, lessThanOrEqualTo(max));
        expect(box.height, lessThanOrEqualTo(max));
      }
    });
  });
}
