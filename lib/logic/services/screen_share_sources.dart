import 'dart:io';
import 'dart:typed_data';

import '../../data/classes/screen_share_settings.dart';
import '../../src/rust/api/screenshare.dart';
import '../../src/rust/api/screenshare/types.dart';
import '../helper_methods.dart';

/// Enumerating what a screen share can capture — screens, windows, and (on
/// Linux) PulseAudio sources.
///
/// This keeps the Rust bridge out of the settings dialog: every call either
/// returns a usable result or an empty one, so the UI never has to reason
/// about platform failures. [pickCaptureSource] is pure and is the only part
/// with a rule worth testing.
class ScreenShareSources {
  const ScreenShareSources._();

  /// Screens (or windows) the platform will let us capture. Returns `[]` if
  /// the platform layer fails, which the dialog renders as "no sources".
  static Future<List<CaptureSource>> listCapture({
    required bool captureFullScreen,
  }) async {
    try {
      final sources = await listCaptureSources(
        captureFullScreen: captureFullScreen,
      );
      final label = captureFullScreen ? 'screen' : 'window';
      for (final source in sources) {
        HelperMethods.printDebug(
          '[CaptureSource][$label] index=${source.index} '
          'title="${source.title}" pid=${source.audioSourcePid}',
        );
      }
      return sources;
    } catch (e) {
      HelperMethods.printDebug('Failed to load capture sources: $e');
      return const [];
    }
  }

  /// A JPEG preview of one source, or null when the platform can't produce
  /// one. Windows is the only platform that supplies these today.
  static Future<Uint8List?> thumbnail({
    required bool captureFullScreen,
    required int sourceIndex,
  }) async {
    try {
      return await getCaptureSourceThumbnail(
        captureFullScreen: captureFullScreen,
        sourceIndex: sourceIndex,
      );
    } catch (e) {
      HelperMethods.printDebug('Thumbnail load failed for source $e');
      return null;
    }
  }

  /// Applications playing sound: PulseAudio sink inputs on Linux (also for
  /// window-capture audio), processes on Windows (for a sound share; a screen
  /// share finds a window's audio by its process). Full-screen capture uses
  /// loopback and never asks.
  static Future<List<AudioSource>> listAudio() async {
    try {
      // A repeated entry would make the picker's value ambiguous, which the
      // dropdown asserts on.
      return withoutRift(
        (await listAudioSources()).toSet().toList(),
        ownBinary: Platform.resolvedExecutable,
      );
    } catch (e) {
      HelperMethods.printDebug('Failed to load audio sources: $e');
      return const [];
    }
  }

  /// [sources] minus every copy of Rift, this one and any other running on
  /// the same machine. What Rift plays is a call, so sharing it puts the call
  /// back into a call: this one's is an echo, and another instance's (a second
  /// profile, a test setup) is no better. Windows already left out this
  /// process alone, and Linux left out nothing (F-10).
  ///
  /// Matched on the executable's file name, case-insensitively, since that is
  /// what both platforms report: `rift.exe` on Windows, `rift` on Linux.
  static List<AudioSource> withoutRift(
    List<AudioSource> sources, {
    required String ownBinary,
  }) {
    final own = ownBinary.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (own.isEmpty) return sources;
    return [
      for (final source in sources)
        if (source.binary.trim().toLowerCase() != own) source,
    ];
  }

  /// What to call an application: its own name, or the binary behind it, and
  /// an empty string when it offered neither. The *media* name is deliberately
  /// not used — it is the track or tab playing, so it changes under you.
  static String appLabel(AudioSource source) {
    for (final candidate in [source.appName, source.binary]) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  /// Which source to select after a (re)load: the one the user picked last
  /// time if it is still there, otherwise the first available, otherwise
  /// nothing. Keeping this pure is what makes "my window disappeared" a
  /// testable case rather than a crash report.
  ///
  /// A window is found again by its title, with its process to tell two of
  /// the same title apart, and by its process alone when the title moved on
  /// (a browser names the tab it shows). Never by its place in the list:
  /// windows open and close between one share and the next, and the place
  /// the last choice held is somebody else's now. Only a choice with no title
  /// — saved before titles were, or a screen without a name — has nothing
  /// else to go by.
  static CaptureSource? pickCaptureSource(
    List<CaptureSource> sources,
    ScreenShareSettings last,
  ) {
    if (sources.isEmpty) return null;
    final title = last.selectedVideoSourceTitle;
    final pid = last.selectedVideoSourcePid;
    if (title != null && title.isNotEmpty) {
      final named = sources.where((s) => s.title == title);
      return named.where((s) => s.audioSourcePid == pid).firstOrNull ??
          named.firstOrNull ??
          (pid == null
              ? null
              : sources.where((s) => s.audioSourcePid == pid).firstOrNull) ??
          sources.first;
    }
    for (final source in sources) {
      if (source.index == last.selectedVideoSourceIndex) return source;
    }
    return sources.first;
  }

  /// Which audio source to select after a (re)load, as the entry *from
  /// [sources]*. Sources compare on every field, title included, and a title
  /// changes whenever the track or tab does — so the previous choice is found
  /// by its stream, then by its app, and never handed back as it was: a value
  /// the list does not contain crashes the dropdown.
  static AudioSource? pickAudioSource(
    List<AudioSource> sources,
    AudioSource? previous,
  ) {
    if (sources.isEmpty) return null;
    if (previous != null) {
      for (final source in sources) {
        if (source.index == previous.index && source.sink == previous.sink) {
          return source;
        }
      }
      if (previous.binary.isNotEmpty || previous.appName.isNotEmpty) {
        for (final source in sources) {
          if (source.binary == previous.binary &&
              source.appName == previous.appName) {
            return source;
          }
        }
      }
    }
    return sources.first;
  }
}
