import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/pcm_level.dart';
import 'package:rift/logic/services/speech_detector.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  SpeechDetector build() =>
      SpeechDetector(threshold: 0.1, hold: const Duration(milliseconds: 400));

  group('SpeechDetector', () {
    test('starts silent', () {
      expect(build().isSpeaking, isFalse);
    });

    test('a loud sample starts speech on the first update', () {
      final d = build();
      expect(d.update(0.5, at(0)), isTrue);
      expect(d.isSpeaking, isTrue);
    });

    test('a sample exactly at the threshold counts as speech', () {
      final d = build();
      expect(d.update(0.1, at(0)), isTrue);
    });

    test('quiet samples alone never start speech', () {
      final d = build();
      for (var ms = 0; ms < 2000; ms += 50) {
        expect(d.update(0.02, at(ms)), isFalse);
      }
      expect(d.isSpeaking, isFalse);
    });

    test('staying loud does not re-report a change', () {
      final d = build();
      d.update(0.5, at(0));
      expect(d.update(0.6, at(50)), isFalse);
      expect(d.update(0.4, at(100)), isFalse);
      expect(d.isSpeaking, isTrue);
    });

    test('speech holds through a short gap between words', () {
      final d = build();
      d.update(0.5, at(0));
      expect(d.update(0.01, at(200)), isFalse);
      expect(d.isSpeaking, isTrue, reason: 'still inside the hold window');
    });

    test('speech ends once the hold window elapses', () {
      final d = build();
      d.update(0.5, at(0));
      expect(d.update(0.01, at(401)), isTrue);
      expect(d.isSpeaking, isFalse);
    });

    test('a blip above the threshold extends the hold', () {
      final d = build();
      d.update(0.5, at(0));
      d.update(0.01, at(300)); // still held
      d.update(0.5, at(350)); // re-arms the hold to 750
      expect(d.update(0.01, at(700)), isFalse);
      expect(d.isSpeaking, isTrue);
      expect(d.update(0.01, at(751)), isTrue);
      expect(d.isSpeaking, isFalse);
    });

    test('reset forces silence, and only reports a change when speaking', () {
      final d = build();
      expect(d.reset(), isFalse);
      d.update(0.5, at(0));
      expect(d.reset(), isTrue);
      expect(d.isSpeaking, isFalse);
    });

    test('reset clears the hold so a stale window cannot revive speech', () {
      final d = build();
      d.update(0.5, at(0));
      d.reset();
      expect(d.update(0.01, at(100)), isFalse);
      expect(d.isSpeaking, isFalse);
    });

    test('the default threshold sits above room noise, below speech', () {
      // Stated in the unit the detector is actually fed — dBFS through
      // PcmLevel — so this test moves if either end of that scale moves.
      final roomNoise = PcmLevel.normalize(-50);
      final quietSpeech = PcmLevel.normalize(-35);
      expect(SpeechDetector.defaultThreshold, greaterThan(roomNoise));
      expect(SpeechDetector.defaultThreshold, lessThan(quietSpeech));
    });
  });
}
