import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../helper_methods.dart';
import 'host_platform.dart';

/// Runs the microphone for a moment, inside the app only, so a call heard
/// muted plays at full quality.
///
/// On Linux the WebRTC library flutter_webrtc ships always
/// installs a render pre-processor in its audio processing module — an
/// empty one unless somebody sets it — and once one is installed, WebRTC
/// plays out the module's own copy of everything it receives rather than
/// the audio itself. That copy runs at the capture rate, and before the
/// microphone has recorded anything the capture rate is the module's default
/// of 16 kHz. So somebody who joined muted heard every voice, every shared
/// game and every song cut off just under 8 kHz until they first unmuted.
/// Measured Oct 10 2026: 7.3 kHz muted from the start, the source's 20 kHz
/// once the microphone had run, and still after muting again. The copy is
/// also mono, whatever arrives; that needs the library itself changed.
///
/// The module only learns the rate from recording, and WebRTC only records
/// for a stream that is sending. So the microphone is sent from one peer
/// connection to another, both in this process, for half a second, and both
/// are closed. Nothing leaves the app and nobody in the call sees the
/// microphone open. The rate then holds until the app quits, so this runs
/// once per session.
///
/// Linux only ([HostPlatform.playoutFollowsMicRate]). Windows uses the same
/// library but measured differently: about 14 kHz joined muted, and the
/// warm-up took it down to 7.4 kHz and made Windows duck other apps.
class PlayoutWarmup {
  const PlayoutWarmup._();

  static bool _done = false;
  static Future<void>? _running;

  /// How long the microphone runs once the two ends are connected.
  static const _recordFor = Duration(milliseconds: 500);

  /// Give up rather than hold a microphone open on a connection that never
  /// comes up.
  static const _connectWithin = Duration(seconds: 5);

  /// Whether the call would still be heard at 16 kHz.
  static bool get needed => HostPlatform.playoutFollowsMicRate && !_done;

  /// Record from the device [options] names, the call's own capture options,
  /// so the warm-up opens the same microphone with the same processing as the
  /// call would. Calls while one is running share it.
  static Future<void> run(AudioCaptureOptions options) {
    if (!needed) return Future.value();
    return _running ??= _run(options).whenComplete(() => _running = null);
  }

  /// Recording happened some other way: the call opened the microphone.
  static void markDone() => _done = true;

  static Future<void> _run(AudioCaptureOptions options) async {
    LocalAudioTrack? track;
    rtc.RTCPeerConnection? sender;
    rtc.RTCPeerConnection? receiver;
    try {
      track = await LocalAudioTrack.create(options);
      sender = await rtc.createPeerConnection({});
      receiver = await rtc.createPeerConnection({});
      final a = sender;
      final b = receiver;
      a.onIceCandidate = (c) => unawaited(b.addCandidate(c));
      b.onIceCandidate = (c) => unawaited(a.addCandidate(c));
      final connected = Completer<void>();
      a.onConnectionState = (state) {
        if (state ==
                rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
            !connected.isCompleted) {
          connected.complete();
        }
      };
      await a.addTrack(track.mediaStreamTrack, track.mediaStream);
      final offer = await a.createOffer();
      await a.setLocalDescription(offer);
      await b.setRemoteDescription(offer);
      final answer = await b.createAnswer();
      await b.setLocalDescription(answer);
      await a.setRemoteDescription(answer);
      await connected.future.timeout(_connectWithin);
      await Future<void>.delayed(_recordFor);
      _done = true;
    } catch (e) {
      // Not worth failing anything over: the call works, at the old quality,
      // and the next join tries again.
      HelperMethods.printDebug('[PlayoutWarmup] skipped: $e');
    } finally {
      await sender?.close();
      await receiver?.close();
      await track?.stop();
    }
  }
}
