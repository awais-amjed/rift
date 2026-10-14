import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/data/classes/share_sound_choice.dart';
import 'package:rift/data/classes/shared_window.dart';
import 'package:rift/logic/services/share_sound_match.dart';
import 'package:rift/logic/services/window_share_portal.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

AudioSource sound(
  int index, {
  String app = '',
  String binary = '',
  String appId = '',
  String media = 'Playback',
  int? pid,
}) => AudioSource(
  index: index,
  sink: 1,
  appName: app,
  binary: binary,
  mediaName: media,
  appId: appId,
  pid: pid,
);

// What each played to PulseAudio on the test machine, Oct 14 2026.
final chrome = sound(
  10,
  app: 'Google Chrome',
  binary: 'chrome',
  appId: 'google-chrome',
  pid: 700,
);
final firefox = sound(
  11,
  app: 'Firefox',
  binary: 'firefox',
  appId: 'firefox',
  media: 'AudioStream',
);
final spotify = sound(12, app: 'spotify', binary: 'spotify', appId: 'spotify');
final mpv = sound(13, app: 'mpv', binary: 'mpv', media: 'song.flac - mpv');

void main() {
  group('ShareSoundMatch.guess', () {
    test('finds a browser by the desktop file GNOME saved', () {
      const window = SharedWindow(
        appId: 'google-chrome.desktop',
        title: 'A video - YouTube - Google Chrome',
      );
      expect(ShareSoundMatch.guess(window, [firefox, chrome]), chrome);
    });

    test('finds a sandboxed app by the word that names it', () {
      const window = SharedWindow(appId: 'com.spotify.Client', title: '');
      expect(ShareSoundMatch.guess(window, [chrome, spotify]), spotify);
    });

    test('finds a reverse-DNS id by its last word', () {
      const window = SharedWindow(appId: 'org.mozilla.firefox', title: '');
      expect(ShareSoundMatch.guess(window, [chrome, firefox]), firefox);
    });

    test('takes the window’s own process first on X11', () {
      final other = sound(20, app: 'Google Chrome', binary: 'chrome', pid: 9);
      const window = SharedWindow(appId: 'google-chrome', title: '', pid: 700);
      expect(ShareSoundMatch.guess(window, [other, chrome]), chrome);
    });

    test('takes a stream from a process the window’s started', () {
      // X11 Chrome: the window is the browser's, the sound its audio
      // helper's (seen Oct 14 2026).
      final helper = sound(21, binary: 'chrome', pid: 702);
      final other = sound(22, app: 'Firefox', binary: 'firefox', pid: 900);
      const window = SharedWindow(appId: 'firefox', title: '', pid: 700);
      final parents = {702: 701, 701: 700, 700: 1, 900: 1};
      expect(
        ShareSoundMatch.guess(window, [
          other,
          helper,
        ], parentOf: (p) => parents[p]),
        helper,
      );
    });

    test('takes the newest of an app’s streams', () {
      final later = sound(
        30,
        app: 'Google Chrome',
        binary: 'chrome',
        appId: 'google-chrome',
      );
      const window = SharedWindow(appId: 'google-chrome.desktop', title: '');
      expect(ShareSoundMatch.guess(window, [chrome, later]), later);
    });

    test('finds a player naming in the title what it plays', () {
      const window = SharedWindow(appId: '', title: 'song.flac - mpv');
      expect(ShareSoundMatch.guess(window, [chrome, mpv]), mpv);
    });

    test('a stream called Playback says nothing about a title', () {
      const window = SharedWindow(appId: '', title: 'Playback notes');
      expect(ShareSoundMatch.guess(window, [chrome]), isNull);
    });

    test('words every desktop id has match nothing', () {
      const window = SharedWindow(appId: 'org.gnome.Nautilus', title: '');
      final shell = sound(40, app: 'GNOME Shell', binary: 'gnome-shell');
      expect(ShareSoundMatch.guess(window, [shell]), isNull);
    });

    test('finds a game by the initials of its title', () {
      // What Counter-Strike 2 played as: a name, and no binary.
      final cs2 = sound(60, app: 'cs2', media: 'cs2');
      const window = SharedWindow(
        appId: 'window:12',
        title: 'Counter-Strike 2',
      );
      expect(ShareSoundMatch.guess(window, [chrome, cs2]), cs2);
    });

    test('two letters of initials are too few to name an app', () {
      final te = sound(61, app: 'te');
      const window = SharedWindow(appId: '', title: 'Text Editor');
      expect(ShareSoundMatch.guess(window, [te]), isNull);
    });

    test('a remembered game is found again without a binary', () {
      final cs2 = sound(60, app: 'cs2', media: 'cs2');
      final again = sound(62, app: 'cs2', media: 'cs2');
      final found = ShareSoundMatch.remembered(ShareSoundChoice.of(cs2), [
        chrome,
        again,
      ]);
      expect(found.source, again);
    });

    test('no match is every app, never some other app', () {
      const window = SharedWindow(appId: 'org.gnome.TextEditor', title: 'x');
      expect(ShareSoundMatch.guess(window, [chrome, spotify]), isNull);
    });
  });

  group('ShareSoundMatch.appKey', () {
    test('keeps the app id bare and in lower case', () {
      const window = SharedWindow(appId: 'Google-Chrome.desktop', title: '');
      expect(ShareSoundMatch.appKey(window), 'google-chrome');
    });

    test('an app GNOME knows only by its window is kept by its title', () {
      // Counter-Strike 2 from Steam, on GNOME 50, Oct 15 2026: the window
      // matched no menu entry, and nothing was ever remembered for it.
      const window = SharedWindow(
        appId: 'window:12',
        title: 'Counter-Strike 2',
      );
      final key = ShareSoundMatch.appKey(window);
      expect(key, 'title:counter-strike 2');
      expect(ShareSoundMatch.byTitle(key!), isTrue);
      expect(
        ShareSoundMatch.appKey(
          const SharedWindow(appId: 'window:31', title: ' Counter-Strike 2'),
        ),
        key,
      );
    });

    test('an app id is never taken for a title', () {
      const window = SharedWindow(appId: 'firefox', title: 'Title');
      expect(ShareSoundMatch.byTitle(ShareSoundMatch.appKey(window)!), isFalse);
    });

    test('has nothing to keep a choice under without an app or a title', () {
      expect(
        ShareSoundMatch.appKey(
          const SharedWindow(appId: 'window:12', title: ''),
        ),
        isNull,
      );
      expect(
        ShareSoundMatch.appKey(const SharedWindow(appId: ' ', title: ' ')),
        isNull,
      );
    });
  });

  group('ShareSoundMatch.remembered', () {
    test('finds the app again in a new stream', () {
      final again = sound(50, app: 'spotify', binary: 'spotify');
      final found = ShareSoundMatch.remembered(ShareSoundChoice.of(spotify), [
        chrome,
        again,
      ]);
      expect(found.found, isTrue);
      expect(found.source, again);
    });

    test('is not found while its app plays nothing', () {
      final found = ShareSoundMatch.remembered(ShareSoundChoice.of(spotify), [
        chrome,
      ]);
      expect(found.found, isFalse);
    });

    test('every app is always found', () {
      final found = ShareSoundMatch.remembered(
        const ShareSoundChoice.allApps(),
        const [],
      );
      expect(found, (found: true, source: null));
    });
  });

  test('remembered sounds survive a restart', () {
    final settings = const ScreenShareSettings().copyWith(
      soundForApps: {
        'google-chrome': ShareSoundChoice.of(chrome),
        'org.gnome.totem': const ShareSoundChoice.allApps(),
      },
      choosesSoundThisTime: true,
    );
    final back = ScreenShareSettings.fromJson(settings.toJson());
    expect(back.soundForApps, settings.soundForApps);
    // Only ever for the share it was ticked for.
    expect(back.choosesSoundThisTime, isFalse);
  });

  test('a GNOME title comes back as it was written', () {
    expect(
      WindowSharePortal.unescape('DON&apos;T &amp; &lt;b&gt; &quot;x&quot;'),
      'DON\'T & <b> "x"',
    );
  });
}
