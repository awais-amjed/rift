/// The native half of [mic_playback.dart]: nothing to play with here.
library;

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Off the web the mic test is never played back this way.
class MicPlayback {
  const MicPlayback._();

  /// Always null off the web.
  static MicPlayback? start(
    MediaStreamTrack track, {
    String? outputDeviceId,
    required double volume,
  }) => null;

  void stop() {}
}
