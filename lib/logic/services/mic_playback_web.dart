/// The web half of [mic_playback.dart] — the real browser calls.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;

import '../helper_methods.dart';

/// The mic test's track playing in an audio element of its own, so you hear
/// what Rift hears. Not attached to the page: an element plays whether or not
/// it is in the document, and one left behind there would outlive the test.
class MicPlayback {
  MicPlayback._(this._audio);

  final web.HTMLAudioElement _audio;

  /// Plays [track] on [outputDeviceId] — a browser device id, or null for the
  /// default — at [volume] (0 to 1). Null when [track] is not a browser one.
  ///
  /// A browser that cannot pick an output (Safari) plays on the default; one
  /// that refuses the device does the same. The test is about the microphone.
  static MicPlayback? start(
    MediaStreamTrack track, {
    String? outputDeviceId,
    required double volume,
  }) {
    if (track is! MediaStreamTrackWeb) return null;
    final audio = web.HTMLAudioElement()
      ..volume = volume.clamp(0, 1)
      ..srcObject = web.MediaStream([track.jsTrack].toJS);
    if (outputDeviceId != null &&
        outputDeviceId.isNotEmpty &&
        audio.has('setSinkId')) {
      audio.setSinkId(outputDeviceId).toDart.catchError((Object e) {
        HelperMethods.printDebug('MicPlayback: output $outputDeviceId – $e');
        return null;
      });
    }
    // Allowed without a further gesture: the test was started by a click.
    audio.play().toDart.catchError((Object e) {
      HelperMethods.printDebug('MicPlayback: play – $e');
      return null;
    });
    return MicPlayback._(audio);
  }

  void stop() {
    _audio.pause();
    _audio.srcObject = null;
  }
}
