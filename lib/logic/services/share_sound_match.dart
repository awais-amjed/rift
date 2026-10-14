import '../../data/classes/share_sound_choice.dart';
import '../../data/classes/shared_window.dart';
import '../../src/rust/api/screenshare/types.dart';

/// Which app's sound goes with a shared window, on Linux, where nothing ties
/// a window to the stream playing its sound. A best guess, shown in the sound
/// popup for the user to confirm, and the choice they asked to keep.
///
/// A guess that is not good names nothing, which is every app but Rift: the
/// window's sound is then heard anyway, with the rest. Picking some other app
/// would drop it.
class ShareSoundMatch {
  const ShareSoundMatch._();

  /// Words in an app's id that say nothing about which app it is.
  static const _filler = {
    'org', 'com', 'io', 'net', 'dev', 'app', 'apps', 'desktop', 'client', //
    'bin', 'stable', 'beta', 'nightly', 'browser', 'player', 'gnome', 'kde',
  };

  /// What players call any stream they open, which no window title would
  /// mean by itself.
  static const _genericMedia = {
    'playback', 'audio stream', 'audiostream', 'output', 'sound', //
    'simple directmedia layer', 'audio', 'stream',
  };

  /// The name a remembered choice is kept under: the window's app id in
  /// lower case, without `.desktop`. Null when the desktop did not say, and
  /// then there is nothing to remember it by.
  static String? appKey(SharedWindow window) {
    final key = _app(window);
    return key.isEmpty ? null : key;
  }

  /// The source most likely playing [window]'s sound, from [sources], or
  /// null for every app.
  ///
  /// In order: the window's own process or one it started (X11 says which,
  /// and a browser plays from a helper process); the app by its id,
  /// whole and then word by word (`com.spotify.Client` is `spotify`); a
  /// player naming what it plays in the window's title. Of several streams
  /// that match, the newest.
  ///
  /// [parentOf] names a process's parent (`ProcessTree.parentOf`).
  static AudioSource? guess(
    SharedWindow window,
    List<AudioSource> sources, {
    int? Function(int pid) parentOf = _noParent,
  }) {
    final pid = window.pid;
    if (pid != null) {
      final own = _newest(
        sources.where((s) => _descends(s.pid, from: pid, parentOf: parentOf)),
      );
      if (own != null) return own;
    }

    final app = _app(window);
    if (app.isNotEmpty) {
      final whole = _newest(sources.where((s) => _names(s).contains(app)));
      if (whole != null) return whole;
      final words = _words(app);
      if (words.isNotEmpty) {
        final shared = _newest(
          sources.where(
            (s) => _names(s).any((name) => _words(name).any(words.contains)),
          ),
        );
        if (shared != null) return shared;
      }
    }

    final title = window.title.toLowerCase();
    if (title.isNotEmpty) {
      return _newest(
        sources.where((s) {
          final media = s.mediaName.trim().toLowerCase();
          return media.length >= 4 &&
              !_genericMedia.contains(media) &&
              title.contains(media);
        }),
      );
    }
    return null;
  }

  /// A remembered [choice] among what is playing now: `found` false when its
  /// app is not playing, and the popup asks again. Every app is always found,
  /// as a null source.
  static ({bool found, AudioSource? source}) remembered(
    ShareSoundChoice choice,
    List<AudioSource> sources,
  ) {
    if (choice.allApps) return (found: true, source: null);
    final source = _newest(
      sources.where(
        (s) => s.binary == choice.binary && s.appName == choice.appName,
      ),
    );
    return (found: source != null, source: source);
  }

  static int? _noParent(int pid) => null;

  /// The window's app id, bare, or empty. GNOME calls an app without a
  /// desktop file `window:<n>`, a number that names nothing next time.
  static String _app(SharedWindow window) {
    final app = _bare(window.appId);
    return app.startsWith('window:') ? '' : app;
  }

  /// Whether [pid] is [from] or was started by it, however far down.
  static bool _descends(
    int? pid, {
    required int from,
    required int? Function(int pid) parentOf,
  }) {
    for (var depth = 0; pid != null && pid > 1 && depth < 32; depth++) {
      if (pid == from) return true;
      pid = parentOf(pid);
    }
    return false;
  }

  /// What a source calls its app, each bare: its id, binary and name.
  static Set<String> _names(AudioSource source) => {
    for (final name in [source.appId, source.binary, source.appName])
      if (_bare(name).isNotEmpty) _bare(name),
  };

  static String _bare(String id) {
    final lower = id.trim().toLowerCase();
    return lower.endsWith('.desktop')
        ? lower.substring(0, lower.length - '.desktop'.length)
        : lower;
  }

  static Set<String> _words(String name) => {
    for (final word in name.split(RegExp(r'[.\-_ ]+')))
      if (word.length > 1 && !_filler.contains(word)) word,
  };

  /// The stream that started last: PulseAudio numbers them in order.
  static AudioSource? _newest(Iterable<AudioSource> sources) {
    AudioSource? newest;
    for (final source in sources) {
      if (newest == null || source.index > newest.index) newest = source;
    }
    return newest;
  }
}
