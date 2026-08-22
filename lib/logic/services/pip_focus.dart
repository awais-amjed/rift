import 'voice_tiles.dart';

/// Which of a call's cells earns the floating window.
///
/// A PiP window is one small rectangle, so this is a ranking and not a layout:
/// a shared screen first, because it is the thing people are looking *at*;
/// then whoever is talking; then anyone else with a camera on.
///
/// Only remote cells are eligible. Your own camera in PiP is a mirror you are
/// not looking into, and your own shared screen is the window drawing itself —
/// neither is worth leaving the app for. Returning null is a real answer: it
/// means the call is audio, and audio belongs in the notification instead of a
/// black rectangle floating over whatever you went to do.
VoiceTile<T>? pipFocus<T>(
  Iterable<VoiceTile<T>> tiles, {
  required bool Function(T) isLocal,
  required bool Function(T) isSpeaking,
  required bool Function(VoiceTile<T>) hasVideo,
}) {
  VoiceTile<T>? screenshare;
  VoiceTile<T>? speaker;
  VoiceTile<T>? camera;

  for (final tile in tiles) {
    if (isLocal(tile.participant)) continue;
    if (!hasVideo(tile)) continue;

    if (tile.isScreenshare) {
      screenshare ??= tile;
      continue;
    }
    if (isSpeaking(tile.participant)) {
      speaker ??= tile;
      continue;
    }
    camera ??= tile;
  }

  return screenshare ?? speaker ?? camera;
}
