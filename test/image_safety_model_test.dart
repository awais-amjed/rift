import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/image_safety.dart';
import 'package:rift/logic/services/image_safety_classifier.dart';

/// The shipped model, run the way the app runs it, against the scores the
/// ONNX original gives the same picture (see rift-models/verify.py). This is
/// the one test that would catch a wrong layout, a wrong channel order, or a
/// resize that does not match the model card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled model answers like the original', () async {
    final Interpreter interpreter;
    try {
      interpreter = Interpreter.fromFile(File(ImageSafetyClassifier.asset));
    } catch (e) {
      // No native LiteRT on this test host; the packing is covered elsewhere.
      markTestSkipped('LiteRT unavailable here: $e');
      return;
    }

    final bytes = File('test/fixtures/safety_sample.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: ImageSafetyClassifier.side,
      targetHeight: ImageSafetyClassifier.side,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final pixels = ImageSafetyClassifier.packPixels(
      rgba,
      ImageSafetyClassifier.side,
    );

    expect(interpreter.getInputTensors().first.shape, [1, 224, 224, 3]);
    final output = [List<double>.filled(3, 0)];
    interpreter.run(pixels.reshape([1, 224, 224, 3]), output);
    final verdict = ImageSafetyVerdict.fromScores(output[0]);

    // Python, same picture, bilinear resize: gore 0.0282, sexual 0.0279,
    // safe 0.9439. The engine's resampler differs slightly, so a loose
    // tolerance — what matters is the class and its margin.
    expect(verdict.safe, closeTo(0.94, 0.05));
    expect(verdict.isSensitive, isFalse);
    interpreter.close();
  });
}
