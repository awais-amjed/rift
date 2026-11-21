import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_clip/clip_output.dart';

/// A clip's preview plays where the call does: on the chosen output, or the
/// system's default when that device is gone, as the call itself falls back.
void main() {
  test('plays on the chosen output', () async {
    final asked = <String?>[];
    final got = await ClipOutput.play<int>('rift_out', (device) async {
      asked.add(device);
      return 7;
    });
    expect(got, 7);
    expect(asked, ['rift_out']);
  });

  test('a device that is gone falls back to the default', () async {
    final asked = <String?>[];
    final got = await ClipOutput.play<int>('rift_game', (device) async {
      asked.add(device);
      if (device != null) throw 'no such output: rift_game';
      return 3;
    });
    expect(got, 3);
    expect(asked, ['rift_game', null]);
  });

  test("WebRTC's default entry, or none, is the default from the start", () async {
    for (final output in [null, '', 'default: Built-in Audio']) {
      final asked = <String?>[];
      await ClipOutput.play<int>(output, (device) async {
        asked.add(device);
        return 1;
      });
      expect(asked, [null], reason: '$output');
    }
  });

  test('a failure on the default itself is not hidden', () async {
    expect(
      ClipOutput.play<int>(null, (_) async => throw 'no output at all'),
      throwsA('no output at all'),
    );
  });
}
