import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_setting.dart';
import 'package:rift/data/enums/app_sound.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

void main() {
  group('AppSound.settingIn', () {
    test('an untouched pair plays at the default level', () {
      final setting = AppSound.presence.settingIn(const {});
      expect(setting.muted, isFalse);
      expect(setting.volume, AppSound.defaultVolume);
    });

    test('a stored pair is read by its name, and only its own', () {
      const all = {'pushToTalk': ParticipantSetting(muted: true, volume: 0.2)};
      expect(AppSound.pushToTalk.settingIn(all).muted, isTrue);
      expect(AppSound.pushToTalk.settingIn(all).volume, 0.2);
      expect(AppSound.stream.settingIn(all).muted, isFalse);
    });
  });

  test('every sound names files that ship', () {
    for (final sound in AppSound.values) {
      for (final asset in [sound.startAsset, ?sound.endAsset]) {
        expect(File('assets/$asset').existsSync(), isTrue, reason: asset);
      }
    }
  });

  test('AppState keeps call sounds across a JSON round-trip', () {
    const state = AppState(
      appSounds: {'watchers': ParticipantSetting(muted: true, volume: 0.3)},
    );
    final restored = AppState.fromJson(state.toJson());
    final watchers = AppSound.watchers.settingIn(restored.appSounds);
    expect(watchers.muted, isTrue);
    expect(watchers.volume, 0.3);
  });

  test('a state saved before call sounds existed loads with none set', () {
    final json = const AppState().toJson()..remove('appSounds');
    expect(AppState.fromJson(json).appSounds, isEmpty);
  });
}
