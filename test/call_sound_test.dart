import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_setting.dart';
import 'package:rift/data/enums/call_sound.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

void main() {
  group('CallSound.settingIn', () {
    test('an untouched pair plays at the default level', () {
      final setting = CallSound.presence.settingIn(const {});
      expect(setting.muted, isFalse);
      expect(setting.volume, CallSound.defaultVolume);
    });

    test('a stored pair is read by its name, and only its own', () {
      const all = {'pushToTalk': ParticipantSetting(muted: true, volume: 0.2)};
      expect(CallSound.pushToTalk.settingIn(all).muted, isTrue);
      expect(CallSound.pushToTalk.settingIn(all).volume, 0.2);
      expect(CallSound.stream.settingIn(all).muted, isFalse);
    });
  });

  test('AppState keeps call sounds across a JSON round-trip', () {
    const state = AppState(
      callSounds: {'watchers': ParticipantSetting(muted: true, volume: 0.3)},
    );
    final restored = AppState.fromJson(state.toJson());
    final watchers = CallSound.watchers.settingIn(restored.callSounds);
    expect(watchers.muted, isTrue);
    expect(watchers.volume, 0.3);
  });

  test('a state saved before call sounds existed loads with none set', () {
    final json = const AppState().toJson()..remove('callSounds');
    expect(AppState.fromJson(json).callSounds, isEmpty);
  });
}
