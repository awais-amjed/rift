import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/clean_picture_gate.dart';

void main() {
  group('CleanPictureGate', () {
    test('a keyframe before decryption began does not open it', () {
      // The garbage itself: an encrypted keyframe decoded as if it were not.
      final gate = CleanPictureGate();
      gate.onKeyFrames(1);
      expect(gate.ready, isFalse);
    });

    test('the keyframe decoded at the moment decryption began does not', () {
      final gate = CleanPictureGate()..onDecrypting(1);
      gate.onKeyFrames(1);
      expect(gate.ready, isFalse);
    });

    test('the next keyframe after decryption began does', () {
      final gate = CleanPictureGate()..onDecrypting(1);
      gate.onKeyFrames(2);
      expect(gate.ready, isTrue);
    });

    test('no count yet counts from zero', () {
      final gate = CleanPictureGate()..onDecrypting(null);
      gate.onKeyFrames(null);
      expect(gate.ready, isFalse);
      gate.onKeyFrames(1);
      expect(gate.ready, isTrue);
    });

    test('a second report of decryption keeps the first baseline', () {
      final gate = CleanPictureGate()
        ..onDecrypting(1)
        ..onDecrypting(5);
      gate.onKeyFrames(2);
      expect(gate.ready, isTrue);
    });

    test('giving up opens it', () {
      final gate = CleanPictureGate()..giveUp();
      expect(gate.ready, isTrue);
    });
  });
}
