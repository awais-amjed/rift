import 'dart:typed_data';

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

  /// PulseAudio sources, for Linux window-capture audio. Full-screen capture
  /// uses loopback and never asks.
  static Future<List<AudioSource>> listAudio() async {
    try {
      return await listAudioSources();
    } catch (e) {
      HelperMethods.printDebug('Failed to load audio sources: $e');
      return const [];
    }
  }

  /// Which source to select after a (re)load: the one the user picked last
  /// time if it is still there, otherwise the first available, otherwise
  /// nothing. Keeping this pure is what makes "my window disappeared" a
  /// testable case rather than a crash report.
  static CaptureSource? pickCaptureSource(
    List<CaptureSource> sources,
    int? persistedIndex,
  ) {
    if (sources.isEmpty) return null;
    for (final source in sources) {
      if (source.index == persistedIndex) return source;
    }
    return sources.first;
  }
}
