import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/pcm_level.dart';

/// One frame of mono 16-bit PCM holding a sine wave of the given peak
/// amplitude (0–1). A sine's RMS is its peak over root two.
Uint8List sineFrame(double amplitude, {int samples = 480}) {
  final pcm = Int16List(samples);
  for (var i = 0; i < samples; i++) {
    final value = math.sin(2 * math.pi * i / samples) * amplitude * 32767;
    pcm[i] = value.round();
  }
  return pcm.buffer.asUint8List();
}

/// A frame whose RMS is exactly [amplitude]: every sample at full deflection,
/// alternating sign. Useful when the expected decibel value must be exact.
Uint8List squareFrame(double amplitude, {int samples = 480}) {
  final pcm = Int16List(samples);
  final magnitude = (amplitude * 32768).round().clamp(0, 32767);
  for (var i = 0; i < samples; i++) {
    pcm[i] = i.isEven ? magnitude : -magnitude;
  }
  return pcm.buffer.asUint8List();
}

/// The level a signal at [db] dBFS should report.
double levelAtDb(double db) => PcmLevel.normalize(db);

void main() {
  group('PcmLevel.rms', () {
    test('digital silence has no amplitude', () {
      expect(PcmLevel.rms(Uint8List(960)), 0);
    });

    test('a full-scale square wave reaches full scale', () {
      expect(PcmLevel.rms(squareFrame(1)), closeTo(1, 0.001));
    });

    test('a sine reads its peak over root two', () {
      expect(PcmLevel.rms(sineFrame(1)), closeTo(1 / math.sqrt2, 0.01));
      expect(PcmLevel.rms(sineFrame(0.5)), closeTo(0.5 / math.sqrt2, 0.01));
    });

    test('survives buffers the sample loop cannot divide evenly', () {
      // A short or odd-length frame is a dropped frame, not a crash.
      expect(PcmLevel.rms(Uint8List(0)), 0);
      expect(PcmLevel.rms(Uint8List(1)), 0);
      expect(PcmLevel.rms(Uint8List(3)), 0);
    });

    test('reads a frame the platform channel handed us at an odd offset', () {
      // asInt16List cannot view an odd byte offset; the level must still be
      // right rather than throwing.
      final frame = squareFrame(0.5);
      final shifted = Uint8List(frame.length + 1)..setRange(1, frame.length + 1, frame);
      final misaligned = Uint8List.view(shifted.buffer, 1, frame.length);

      expect(misaligned.offsetInBytes.isOdd, isTrue);
      expect(PcmLevel.rms(misaligned), closeTo(0.5, 0.001));
    });
  });

  group('PcmLevel.toDb', () {
    test('full scale is 0 dBFS', () {
      expect(PcmLevel.toDb(1), closeTo(0, 0.001));
    });

    test('halving the amplitude costs about six decibels', () {
      expect(PcmLevel.toDb(0.5), closeTo(-6.02, 0.01));
      expect(PcmLevel.toDb(0.25), closeTo(-12.04, 0.01));
    });

    test('silence bottoms out at the floor instead of minus infinity', () {
      expect(PcmLevel.toDb(0), PcmLevel.floorDb);
      expect(PcmLevel.toDb(0.0000001), PcmLevel.floorDb);
    });
  });

  group('PcmLevel.normalize', () {
    test('spans the floor to full scale', () {
      expect(PcmLevel.normalize(PcmLevel.floorDb), 0);
      expect(PcmLevel.normalize(0), 1);
    });

    test('is linear in decibels, so the slider moves evenly', () {
      // The property the old band-peak scale lacked: the same movement means
      // the same loudness change wherever you are on the control.
      final quarter = PcmLevel.normalize(PcmLevel.floorDb * 0.75);
      final half = PcmLevel.normalize(PcmLevel.floorDb * 0.5);
      final threeQuarters = PcmLevel.normalize(PcmLevel.floorDb * 0.25);

      expect(half - quarter, closeTo(threeQuarters - half, 1e-9));
      expect(half, closeTo(0.5, 1e-9));
    });

    test('clamps rather than running off either end', () {
      expect(PcmLevel.normalize(-200), 0);
      expect(PcmLevel.normalize(12), 1);
    });
  });

  group('PcmLevel.fromInt16', () {
    test('is monotonic, so louder never draws shorter', () {
      var previous = -1.0;
      for (final amplitude in [0.0, 0.001, 0.01, 0.05, 0.2, 0.5, 1.0]) {
        final level = PcmLevel.fromInt16(squareFrame(amplitude));
        expect(level, greaterThan(previous));
        previous = level;
      }
    });

    test('leaves a usable gap between a quiet room and speech', () {
      // This is the whole point of the change. Room tone lands near the bottom
      // of the scale and speech near the middle, so a threshold has somewhere
      // to sit. Under the old band-peak scale both crowded into the bottom
      // tenth and no slider position could separate them.
      final roomTone = levelAtDb(-50);
      final quietSpeech = levelAtDb(-35);
      final speech = levelAtDb(-25);

      expect(roomTone, lessThan(0.2));
      expect(quietSpeech, greaterThan(0.35));
      expect(speech, greaterThan(0.55));
      expect(quietSpeech - roomTone, greaterThan(0.2));
    });

    test('measured levels match the decibel figures they stand for', () {
      // Guards the meter against drifting away from the unit it claims: a
      // signal generated at a known amplitude must read where dBFS says.
      for (final db in [-6.0, -20.0, -40.0]) {
        final amplitude = math.pow(10, db / 20).toDouble();
        expect(
          PcmLevel.fromInt16(squareFrame(amplitude)),
          closeTo(levelAtDb(db), 0.005),
          reason: '$db dBFS',
        );
      }
    });
  });
}
