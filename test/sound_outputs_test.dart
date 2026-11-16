import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/sound_outputs.dart';

void main() {
  group('SoundOutputs', () {
    test('every kind follows the output until it is given its own', () {
      const outputs = SoundOutputs();
      for (final kind in SoundKind.values) {
        expect(outputs.deviceFor(kind, 'headset'), 'headset');
        expect(outputs.deviceFor(kind, null), isNull);
      }
      expect(outputs.isSplit, isFalse);
    });

    test('a kind given a device plays there, whatever the output', () {
      final outputs = const SoundOutputs().withChoice(
        SoundKind.streams,
        'media',
      );
      expect(outputs.deviceFor(SoundKind.streams, 'headset'), 'media');
      expect(outputs.deviceFor(SoundKind.streams, null), 'media');
      expect(outputs.deviceFor(SoundKind.calls, 'headset'), 'headset');
      expect(outputs.deviceFor(SoundKind.dings, 'headset'), 'headset');
      expect(outputs.isSplit, isTrue);
    });

    test('system default is a choice of its own, not "same as output"', () {
      final outputs = const SoundOutputs().withChoice(
        SoundKind.dings,
        SoundOutputs.systemDefault,
      );
      expect(outputs.deviceFor(SoundKind.dings, 'headset'), isNull);
      expect(outputs.choiceFor(SoundKind.dings), SoundOutputs.systemDefault);
    });

    test('null puts a kind back on the output', () {
      final outputs = const SoundOutputs()
          .withChoice(SoundKind.calls, 'chat')
          .withChoice(SoundKind.calls, null);
      expect(outputs.deviceFor(SoundKind.calls, 'headset'), 'headset');
      expect(outputs, const SoundOutputs());
    });

    test('round-trips through JSON, and reads a missing record as none', () {
      final outputs = const SoundOutputs()
          .withChoice(SoundKind.calls, 'chat')
          .withChoice(SoundKind.streams, 'media')
          .withChoice(SoundKind.dings, SoundOutputs.systemDefault);
      expect(SoundOutputs.fromJson(outputs.toJson()), outputs);
      expect(SoundOutputs.fromJson(const {}), const SoundOutputs());
      expect(
        SoundOutputs.fromJson(const {'calls': 3, 'streams': true}),
        const SoundOutputs(),
      );
    });
  });
}
