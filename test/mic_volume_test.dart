import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/services/mic_volume.dart';

void main() {
  test('100% sends the microphone as it is', () {
    expect(MicVolume.gain(1), 1);
  });

  test('the slider reads up to 200% and sends four times at the top', () {
    expect(MicVolume.max, 2);
    expect(MicVolume.gain(MicVolume.max), 4);
    expect(MicVolume.gain(1.5), 2.5);
  });

  test('below 100% it sends the reading cubed', () {
    expect(MicVolume.gain(0.5), closeTo(0.125, 1e-9));
    expect(MicVolume.gain(0), 0);
  });

  test('the mic volume starts at 100% and survives a JSON round-trip', () {
    expect(const AppState().inputVolume, 1.0);
    const state = AppState(inputVolume: 1.6);
    expect(AppState.fromJson(state.toJson()).inputVolume, 1.6);
  });

  test('a state saved before the mic volume existed sends at 100%', () {
    final json = const AppState().toJson()..remove('inputVolume');
    expect(AppState.fromJson(json).inputVolume, 1.0);
  });

  test('hidden where the runner has no filter', () {
    // The test runs on the host VM, outside the runner, so nothing exports
    // the filter and the slider stays hidden: the same answer a build
    // without the filter gets.
    expect(MicVolume.adjustable, isFalse);
  });
}
