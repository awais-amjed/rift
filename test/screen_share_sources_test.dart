import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/logic/services/screen_share_sources.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

CaptureSource src(int index, {int? pid, String? title}) => CaptureSource(
  index: index,
  title: title ?? 'source $index',
  audioSourcePid: pid,
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
}
