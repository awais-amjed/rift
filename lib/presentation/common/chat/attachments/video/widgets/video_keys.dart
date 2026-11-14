import 'package:flutter/services.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../clip_playback.dart';

/// The keys of a video opened from its card (`VideoViewerPage`): space or
/// k plays and pauses, the arrows go 5 s either way and j and l 10 s, up
/// and down change the volume, m mutes, 0 to 9 jump to that tenth, f goes
/// in and out of full screen and Esc goes back.
class VideoKeys {
  const VideoKeys._();

  /// Whether [event] was one of them, and has been done.
  static bool act(
    KeyEvent event, {
    required ClipPlayback playback,
    required AppCubit app,
    required VoidCallback toggle,
    required VoidCallback fullscreen,
    required VoidCallback back,
  }) {
    if (event is KeyUpEvent) return false;
    final p = playback;
    final key = event.logicalKey;
    void volumeBy(double by) =>
        app.setChatVideoVolume(app.state.chatVideoVolume + by);

    if (key == LogicalKeyboardKey.arrowLeft) {
      p.skip(const Duration(seconds: -5));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      p.skip(const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      volumeBy(0.1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      volumeBy(-0.1);
    } else if (event is KeyRepeatEvent) {
      return false;
    } else if (key == LogicalKeyboardKey.escape) {
      back();
    } else if (key == LogicalKeyboardKey.keyF) {
      fullscreen();
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK) {
      toggle();
    } else if (key == LogicalKeyboardKey.keyJ) {
      p.skip(const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.keyL) {
      p.skip(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.keyM) {
      app.setChatVideoMuted(!app.state.chatVideoMuted);
    } else if (_tenth(key) case final tenth?) {
      p.seek(p.length * (tenth / 10));
    } else {
      return false;
    }
    return true;
  }

  static int? _tenth(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length != 1) return null;
    final digit = label.codeUnitAt(0) - 0x30;
    return digit >= 0 && digit <= 9 ? digit : null;
  }
}
