import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/image_safety_classifier.dart';

void main() {
  // A 2×2 RGBA image: red, green / blue, white — alpha varies to prove it is
  // dropped.
  final rgba = ByteData.sublistView(
    Uint8List.fromList([
      255, 0, 0, 255, //
      0, 255, 0, 128, //
      0, 0, 255, 0, //
      255, 255, 255, 64, //
    ]),
  );

  group('packing pixels for the model', () {
    test('NHWC keeps each pixel\'s channels together, alpha dropped', () {
      final out = ImageSafetyClassifier.packPixels(rgba, 2);
      expect(out, [
        255, 0, 0, //
        0, 255, 0, //
        0, 0, 255, //
        255, 255, 255, //
      ]);
    });

    test('NCHW lays out a plane per channel', () {
      final out = ImageSafetyClassifier.packPixels(
        rgba,
        2,
        channelsFirst: true,
      );
      expect(out, [
        255, 0, 0, 255, // R plane
        0, 255, 0, 255, // G plane
        0, 0, 255, 255, // B plane
      ]);
    });

    test('values stay 0–255: normalisation is the graph\'s job', () {
      final out = ImageSafetyClassifier.packPixels(rgba, 2);
      expect(out.reduce((a, b) => a > b ? a : b), 255);
    });
  });
}
