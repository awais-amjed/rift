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
      expect(MicLevelScale.toMeter(0.9), 1.0);
    });

    test('is monotonic, so louder never draws shorter', () {
      var previousPosition = -1.0;
      var previousMeter = -1.0;
      for (var level = 0.0; level <= 0.4; level += 0.01) {
        final position = MicLevelScale.toPosition(level);
        final meter = MicLevelScale.toMeter(level);
        expect(position, greaterThanOrEqualTo(previousPosition));
        expect(meter, greaterThanOrEqualTo(previousMeter));
        previousPosition = position;
        previousMeter = meter;
      }
    });

    test('the meter leaves speech in the green', () {
      // The bug this replaces: the meter was drawn through the slider's curve,
      // which put room noise a third of the way along the bar and ordinary
      // speech into the amber and red segments (MicLevelMeter colours at 60%
      // and 85%). Nothing was wrong with the microphone; the ruler was.
      expect(MicLevelScale.toMeter(0.03), lessThan(0.2)); // room noise
      expect(
        MicLevelScale.toMeter(SpeechDetector.defaultThreshold),
        lessThan(0.6),
      ); // quiet speech, still green
      expect(MicLevelScale.toMeter(0.15), lessThan(0.6)); // normal speech
      // A raised voice is allowed to reach amber — that part was never wrong.
      expect(MicLevelScale.toMeter(0.25), greaterThan(0.6));
    });

    test('the meter stays comparable with the marker drawn on it', () {
      // Both go through toMeter, so "the bar is past the line" means "the gate
      // is open". Any transform would do, so long as it is the same one.
      const threshold = 0.08;
      expect(
        MicLevelScale.toMeter(0.12) > MicLevelScale.toMeter(threshold),
        isTrue,
      );
      expect(
        MicLevelScale.toMeter(0.05) > MicLevelScale.toMeter(threshold),
        isFalse,
      );
    });
  });
}
