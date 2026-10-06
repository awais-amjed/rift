import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/chat/attachments/attachment_image_thumb.dart';
import 'package:rift/presentation/common/chat/link_preview_card.dart';

/// The box a thumbnail reserves before its bytes arrive. Getting this wrong
/// is what made the message list jump: the placeholder and the decoded image
/// have to occupy exactly the same space.
void main() {
  const maxW = AttachmentImageThumb.maxWidth;
  const maxH = AttachmentImageThumb.maxHeight;

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
      final box = AttachmentImageThumb.boxFor(1600, 800)!;
      expect(box.width, maxW);
      expect(box.height, maxW / 2);
    });

    test('a portrait image is capped on its height', () {
      final box = AttachmentImageThumb.boxFor(800, 1600)!;
      expect(box.height, maxH);
      expect(box.width, maxH / 2);
    });

    test('a square image is capped on the lower ceiling', () {
      final box = AttachmentImageThumb.boxFor(1000, 1000)!;
      expect(box.width, maxH);
      expect(box.height, maxH);
    });

    test('a picture is about a link preview wide, not a thumbnail', () {
      final box = AttachmentImageThumb.boxFor(1920, 1080)!;
      expect(box.width, greaterThanOrEqualTo(LinkPreviewCard.maxWidth));
    });

    test('a narrow message fits the picture to the width it has', () {
      final box = AttachmentImageThumb.boxFor(1920, 1080, within: 300)!;
      expect(box.width, 300);
      expect(box.height, closeTo(300 * 1080 / 1920, 0.001));
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
      for (final (w, h) in [
        (4000, 30),
        (30, 4000),
        (441, 341),
        (439, 500),
        (500, 339),
      ]) {
        for (final within in [maxW, 250.0]) {
          final box = AttachmentImageThumb.boxFor(w, h, within: within)!;
          expect(box.width, lessThanOrEqualTo(within));
          expect(box.height, lessThanOrEqualTo(maxH));
        }
      }
    });
  });
}
