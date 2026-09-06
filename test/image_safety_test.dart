import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/image_safety.dart';

void main() {
  group('the safety verdict', () {
    test('reads the model\'s class order: gore, sexual, safe', () {
      final v = ImageSafetyVerdict.fromScores([0.1, 0.2, 0.7]);
      expect(v.gore, 0.1);
      expect(v.sexual, 0.2);
      expect(v.safe, 0.7);
    });

    test('covers anything the model is not fairly sure is safe', () {
      expect(
        ImageSafetyVerdict.fromScores([0.0, 0.05, 0.95]).isSensitive,
        isFalse,
      );
      // Only just safe by argmax, but not sure enough: covered.
      expect(
        ImageSafetyVerdict.fromScores([0.2, 0.3, 0.5]).isSensitive,
        isTrue,
      );
      expect(
        ImageSafetyVerdict.fromScores([0.0, 0.9, 0.1]).isSensitive,
        isTrue,
      );
      expect(
        ImageSafetyVerdict.fromScores([0.8, 0.1, 0.1]).isSensitive,
        isTrue,
      );
    });

    test('refuses a score list of the wrong shape', () {
      expect(
        () => ImageSafetyVerdict.fromScores([0.5, 0.5]),
        throwsArgumentError,
      );
    });
  });
}
