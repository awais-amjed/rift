import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

void main() {
  test('asking before a voice switch is on until turned off', () {
    expect(const AppState().askBeforeVoiceSwitch, isTrue);
  });

  test('turning it off survives a JSON round-trip', () {
    const state = AppState(askBeforeVoiceSwitch: false);
    expect(AppState.fromJson(state.toJson()).askBeforeVoiceSwitch, isFalse);
  });

  test('a state saved before the setting existed asks', () {
    final json = const AppState().toJson()..remove('askBeforeVoiceSwitch');
    expect(AppState.fromJson(json).askBeforeVoiceSwitch, isTrue);
  });
}
