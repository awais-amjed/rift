import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/mic_level_scale.dart';
import 'package:rift/logic/services/speech_detector.dart';

void main() {
  group('MicLevelScale', () {
    test('round-trips a position through a level and back', () {
      for (final position in [0.0, 0.15, 0.5, 0.83, 1.0]) {
        expect(
          MicLevelScale.toPosition(MicLevelScale.toLevel(position)),
          closeTo(position, 1e-9),
        );
      }
    });

    test('off stays off', () {
      // 0 must mean an open mic exactly, not "very quiet" — the gate treats
      // any threshold above zero as active.
      expect(MicLevelScale.toLevel(0), 0);
      expect(MicLevelScale.toPosition(0), 0);
    });

    test('the whole slider lands on levels a voice can actually reach', () {
      // The bug this replaces: a linear 0–1 slider, where everything past
      // roughly a quarter demanded more than any human voice produces.
      expect(MicLevelScale.toLevel(1), MicLevelScale.maxThreshold);
      expect(MicLevelScale.maxThreshold, lessThan(0.5));
      // A raised voice (~0.25 by SpeechDetector's own reckoning) must still be
      // inside the range, or the top of the slider is decorative.
      expect(MicLevelScale.maxThreshold, greaterThan(0.25));
    });

    test('spends most of its travel below the speech threshold', () {
      // Where the decisions are: separating a quiet talker from room noise.
      // Half the slider should still be under normal speech.
      final atHalf = MicLevelScale.toLevel(0.5);
      expect(atHalf, lessThan(SpeechDetector.defaultThreshold * 1.5));
      expect(atHalf, greaterThan(0.03)); // above room noise
    });

    test('a shout pegs the meter instead of running off the end', () {
      expect(MicLevelScale.toPosition(0.9), 1.0);
      expect(MicLevelScale.toPosition(MicLevelScale.maxThreshold), 1.0);
    });

    test('is monotonic, so louder never draws shorter', () {
      var previous = -1.0;
      for (var level = 0.0; level <= 0.4; level += 0.01) {
        final position = MicLevelScale.toPosition(level);
        expect(position, greaterThanOrEqualTo(previous));
        previous = position;
      }
    });
  });
}
