import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/avatar_image.dart';

void main() {
  group('AvatarImage.isSupportedMime', () {
    test('accepts the common image types', () {
      for (final mime in ['image/png', 'image/jpeg', 'image/webp']) {
        expect(AvatarImage.isSupportedMime(mime), isTrue, reason: mime);
      }
    });

    test('is case-insensitive', () {
      expect(AvatarImage.isSupportedMime('IMAGE/PNG'), isTrue);
    });

    test('rejects non-images and null', () {
      expect(AvatarImage.isSupportedMime('application/pdf'), isFalse);
      expect(AvatarImage.isSupportedMime('text/plain'), isFalse);
      expect(AvatarImage.isSupportedMime(null), isFalse);
    });

    // An SVG would render fine locally but is a script-bearing format; keeping
    // it out of a bucket every member fetches is deliberate.
    test('rejects svg', () {
      expect(AvatarImage.isSupportedMime('image/svg+xml'), isFalse);
    });
  });

  group('AvatarImage.isAcceptableSize', () {
    test('rejects empty and oversized sources', () {
      expect(AvatarImage.isAcceptableSize(0), isFalse);
      expect(AvatarImage.isAcceptableSize(-1), isFalse);
      expect(
        AvatarImage.isAcceptableSize(AvatarImage.maxSourceBytes + 1),
        isFalse,
      );
    });

    test('accepts up to the limit inclusive', () {
      expect(AvatarImage.isAcceptableSize(1), isTrue);
      expect(AvatarImage.isAcceptableSize(AvatarImage.maxSourceBytes), isTrue);
    });
  });

  group('AvatarImage.fitWithin', () {
    test('leaves an already-small image alone rather than upscaling', () {
      expect(AvatarImage.fitWithin(64, 48), (width: 64, height: 48));
    });

    test('scales a landscape image by its width', () {
      expect(AvatarImage.fitWithin(1024, 512), (width: 256, height: 128));
    });

    test('scales a portrait image by its height', () {
      expect(AvatarImage.fitWithin(512, 1024), (width: 128, height: 256));
    });

    test('a square image stays square', () {
      final fit = AvatarImage.fitWithin(4000, 4000);
      expect(fit.width, fit.height);
      expect(fit.width, AvatarImage.maxDimension);
    });

    test('an extreme aspect ratio never collapses to zero', () {
      final fit = AvatarImage.fitWithin(8000, 3);
      expect(fit.width, AvatarImage.maxDimension);
      expect(fit.height, greaterThanOrEqualTo(1));
    });

    test('degenerate dimensions fall back to the max box', () {
      expect(AvatarImage.fitWithin(0, 0).width, AvatarImage.maxDimension);
    });

    test('never exceeds the max on either edge', () {
      for (final size in [(3000, 100), (100, 3000), (257, 257), (255, 300)]) {
        final fit = AvatarImage.fitWithin(size.$1, size.$2);
        expect(fit.width, lessThanOrEqualTo(AvatarImage.maxDimension));
        expect(fit.height, lessThanOrEqualTo(AvatarImage.maxDimension));
      }
    });
  });

  group('AvatarImage.prepare', () {
    test('returns null for bytes that are not an image', () async {
      final garbage = Uint8List.fromList(List.filled(64, 7));
      expect(await AvatarImage.prepare(garbage), isNull);
    });

    test('returns null for an empty source', () async {
      expect(await AvatarImage.prepare(Uint8List(0)), isNull);
    });
  });
}
