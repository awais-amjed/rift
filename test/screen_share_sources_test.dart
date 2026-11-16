import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/audio_app_heard.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/services/screen_share_sources.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

CaptureSource src(int index, {int? pid, String? title}) => CaptureSource(
  index: index,
  title: title ?? 'source $index',
  audioSourcePid: pid,
  appId: '',
  minimised: false,
);

/// What was saved after picking [source] last time.
ScreenShareSettings pickedLast(CaptureSource source) =>
    const ScreenShareSettings().withVideoSource(source);

void main() {
  group('ScreenShareSources.pickCaptureSource', () {
    test('finds the window picked last time wherever it sits now', () {
      // Explorer was second; a window opened since and took its place.
      final last = pickedLast(src(1, title: 'Explorer', pid: 10));
      final picked = ScreenShareSources.pickCaptureSource([
        src(0, title: 'Console', pid: 30),
        src(1, title: 'Notepad', pid: 20),
        src(2, title: 'Explorer', pid: 10),
      ], last);
      expect(picked?.title, 'Explorer');
      expect(picked?.index, 2);
    });

    test('tells two windows of the same title apart by their process', () {
      final picked = ScreenShareSources.pickCaptureSource([
        src(0, title: 'Home', pid: 10),
        src(1, title: 'Home', pid: 11),
      ], pickedLast(src(0, title: 'Home', pid: 11)));
      expect(picked?.index, 1);
    });

    test('follows the process when the title moved on', () {
      final picked = ScreenShareSources.pickCaptureSource([
        src(0, title: 'Console', pid: 30),
        src(1, title: 'Another tab - Browser', pid: 40),
      ], pickedLast(src(0, title: 'A tab - Browser', pid: 40)));
      expect(picked?.index, 1);
    });

    test('falls back to the first when that window is gone', () {
      final picked = ScreenShareSources.pickCaptureSource([
        src(3),
        src(4),
      ], pickedLast(src(4, title: 'Gone', pid: 99)));
      expect(picked?.index, 3);
    });

    test('goes by place only for a choice saved without a title', () {
      const saved = ScreenShareSettings(selectedVideoSourceIndex: 7);
      expect(
        ScreenShareSources.pickCaptureSource([
          src(1),
          src(7),
          src(9),
        ], saved)?.index,
        7,
      );
    });

    test('falls back to the first when nothing was persisted', () {
      expect(
        ScreenShareSources.pickCaptureSource([
          src(3),
          src(4),
        ], const ScreenShareSettings())?.index,
        3,
      );
    });

    test('picks nothing when there are no sources', () {
      expect(
        ScreenShareSources.pickCaptureSource(
          [],
          pickedLast(src(7, title: 'Game')),
        ),
        isNull,
      );
    });
  });

  group('ScreenShareSources.pickAudioSource', () {
    AudioSource audio(
      int index, {
      int sink = 1,
      String app = 'Firefox',
      String binary = 'firefox',
      String title = 'a tab',
    }) => AudioSource(
      index: index,
      sink: sink,
      appName: app,
      binary: binary,
      mediaName: title,
      appId: '',
      playing: true,
    );

    test(
      'keeps the same stream, as the fresh entry, after its title moved',
      () {
        final fresh = audio(5, title: 'the next song');
        final picked = ScreenShareSources.pickAudioSource([
          audio(2, app: 'mpv', binary: 'mpv'),
          fresh,
        ], audio(5, title: 'a song'));
        expect(identical(picked, fresh), isTrue);
      },
    );

    test('follows the app when its stream was replaced', () {
      final picked = ScreenShareSources.pickAudioSource([
        audio(2, app: 'mpv', binary: 'mpv'),
        audio(9),
      ], audio(5));
      expect(picked?.index, 9);
    });

    test('falls back to the first when the app is gone', () {
      final picked = ScreenShareSources.pickAudioSource([
        audio(2, app: 'mpv', binary: 'mpv'),
      ], audio(5));
      expect(picked?.index, 2);
    });

    test(
      'picks the first when nothing was chosen, and nothing from nothing',
      () {
        expect(ScreenShareSources.pickAudioSource([audio(3)], null)?.index, 3);
        expect(ScreenShareSources.pickAudioSource(const [], audio(3)), isNull);
      },
    );

    // A Linux screen share: no source is every app but Rift.
    test('a screen share starts on every app, not the first one', () {
      expect(ScreenShareSources.keepAudioSource([audio(3)], null), isNull);
    });

    test('a screen share keeps the app picked while it plays', () {
      final fresh = audio(9, title: 'the next song');
      final picked = ScreenShareSources.keepAudioSource([
        audio(2, app: 'mpv', binary: 'mpv'),
        fresh,
      ], audio(5));
      expect(identical(picked, fresh), isTrue);
    });

    test('a screen share goes back to every app when the app is gone', () {
      final picked = ScreenShareSources.keepAudioSource([
        audio(2, app: 'mpv', binary: 'mpv'),
      ], audio(5));
      expect(picked, isNull);
    });
  });

  // F-10: the Share sound picker offered other Rift windows on the same PC,
  // and sharing one sends a call back into a call.
  group('ScreenShareSources.withoutRift', () {
    AudioSource audio(String app, String binary) => AudioSource(
      index: app.length,
      sink: 0,
      appName: app,
      binary: binary,
      mediaName: '',
      appId: '',
      playing: true,
    );

    test('drops every Rift on Windows, whatever the case', () {
      final kept = ScreenShareSources.withoutRift([
        audio('rift', 'rift.exe'),
        audio('Rift', 'RIFT.EXE'),
        audio('Spotify', 'Spotify.exe'),
      ], ownBinary: r'C:\Program Files\Rift\rift.exe');
      expect(kept.map((s) => s.appName), ['Spotify']);
    });

    test('drops every Rift on Linux', () {
      final kept = ScreenShareSources.withoutRift([
        audio('rift', 'rift'),
        audio('Firefox', 'firefox'),
      ], ownBinary: '/opt/rift/bundle/rift');
      expect(kept.map((s) => s.appName), ['Firefox']);
    });

    test('keeps a different program that merely says rift', () {
      final kept = ScreenShareSources.withoutRift([
        audio('rift', 'rift-player'),
      ], ownBinary: '/opt/rift/bundle/rift');
      expect(kept, hasLength(1));
    });
  });

  // Nov 16 2026: a paused player has no stream on Linux, so it was not
  // listed and a share could not pick it.
  group('ScreenShareSources.noteHeard', () {
    AudioSource audio(String app, String binary, {bool playing = true}) =>
        AudioSource(
          index: app.length,
          sink: 0,
          appName: app,
          binary: binary,
          mediaName: 'a track',
          appId: '$binary.desktop',
          playing: playing,
        );

    test(
      'puts what plays first, once each, and keeps no more than the limit',
      () {
        final known = [
          for (var i = 0; i < ScreenShareSources.maxAppsHeard; i++)
            AudioAppHeard(binary: 'app$i', appName: 'App $i', appId: ''),
        ];
        final next = ScreenShareSources.noteHeard(known, [
          audio('Google Chrome', 'chrome'),
          audio('App 3', 'app3'),
        ]);
        expect(next.length, ScreenShareSources.maxAppsHeard);
        expect(next.take(3).map((a) => a.binary), ['chrome', 'app3', 'app0']);
        expect(next.first.appId, 'chrome.desktop');
        expect(next.where((a) => a.binary == 'app3').length, 1);
      },
    );

    test('notes neither a quiet entry nor one naming no program', () {
      final next = ScreenShareSources.noteHeard(const [], [
        audio('Google Chrome', 'chrome', playing: false),
        audio('', ''),
      ]);
      expect(next, isEmpty);
    });

    test('a quiet program is never taken for a stream with its number', () {
      final quiet = AudioAppHeard(
        binary: 'chrome',
        appName: 'Google Chrome',
        appId: 'google-chrome',
      ).toSource();
      final stream = AudioSource(
        index: 0,
        sink: 0,
        appName: 'mpv',
        binary: 'mpv',
        mediaName: '',
        appId: '',
        playing: true,
      );
      expect(ScreenShareSources.keepAudioSource([stream], quiet), isNull);
      expect(quiet.playing, isFalse);
    });

    test('a heard app keeps its names through JSON', () {
      const heard = AudioAppHeard(
        binary: 'chrome',
        appName: 'Google Chrome',
        appId: 'google-chrome',
      );
      expect(AudioAppHeard.fromJson(heard.toJson()), heard);
    });
  });
}
