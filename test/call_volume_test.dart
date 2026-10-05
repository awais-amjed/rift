import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_setting.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/services/call_volume.dart';

void main() {
  test('off the web a call can go to 200%', () {
    expect(CallVolume.max, 2.0);
  });

  test('the call volume plays as it reads up to 100%, then three for one', () {
    const asSent = ParticipantSetting();
    expect(CallVolume.of(asSent, 0.5), 0.5);
    expect(CallVolume.of(asSent, 1.0), 1.0);
    expect(CallVolume.of(asSent, 1.5), 2.5);
    expect(CallVolume.of(asSent, 2.0), 4.0);
  });

  test("a person's volume and the call volume multiply", () {
    const loud = ParticipantSetting(volume: 2.0);
    expect(CallVolume.of(loud, 1.0), 2.0);
    expect(CallVolume.of(loud, 2.0), 8.0);
    expect(CallVolume.of(const ParticipantSetting(volume: 0.5), 1.0), 0.5);
  });

  test('both at the top stay inside the 10x libwebrtc allows', () {
    const loud = ParticipantSetting(volume: 2.0);
    expect(CallVolume.of(loud, CallVolume.max), lessThanOrEqualTo(10));
  });

  test('a muted person is silent at any volume', () {
    const muted = ParticipantSetting(muted: true, volume: 2.0);
    expect(CallVolume.of(muted, 2.0), 0);
  });

  test('the call volume starts at 100% and survives a JSON round-trip', () {
    expect(const AppState().outputVolume, 1.0);
    const state = AppState(outputVolume: 1.8);
    expect(AppState.fromJson(state.toJson()).outputVolume, 1.8);
  });

  test('a state saved before the call volume existed plays at 100%', () {
    final json = const AppState().toJson()..remove('outputVolume');
    expect(AppState.fromJson(json).outputVolume, 1.0);
  });
}
