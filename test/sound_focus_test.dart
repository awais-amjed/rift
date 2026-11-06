import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/sound_service.dart';

/// Rift's sounds play beside other apps on Android, never instead of them.
///
/// A player's default takes the whole audio focus, which paused a video in
/// YouTube or Jellyfin for a half-second cue, and it stayed paused.
void main() {
  test('takes no audio focus and leaves the audio mode normal', () {
    final android = SoundService.playBesideOtherApps.android;

    expect(android.audioFocus, AndroidAudioFocus.none);
    expect(android.audioMode, AndroidAudioMode.normal);
    expect(android.usageType, AndroidUsageType.media);
    expect(android.isSpeakerphoneOn, isFalse);
  });

  test('only SoundService sets an audio context', () {
    // Setting one on Android writes the phone's audio mode as well, so doing
    // it during a call would take the call out of its communication mode.
    const pattern = 'setAudioContext(';
    final setters = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains(pattern))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();

    expect(setters, ['lib/logic/services/sound_service.dart']);
  });
}
