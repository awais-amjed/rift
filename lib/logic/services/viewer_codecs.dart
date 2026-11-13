import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show getRtpReceiverCapabilities;

import '../../src/rust/api/screenshare/types.dart';
import '../../src/rust/api/watching.dart';
import '../helper_methods.dart';
import 'rust_watch.dart';
import 'voice_attributes.dart';

/// What this device can play of somebody's share, which it tells the call
/// (`VoiceAttributes.playsKey`) so a sharer can pick something it can play.
///
/// WebRTC is asked about VP8 and VP9, and about H264 on phones and in browsers,
/// whose decoders are the system's or the browser's. On Linux and Windows H264 is
/// only said where the GPU decodes it: libwebrtc lists it there too, but would decode
/// it on the CPU, which Rift does not use, so such a viewer brings the share down to
/// VP9. On Linux and Windows H265 is said only by the Rust watch connection on a GPU
/// that decodes it, whatever WebRTC lists. An Android phone says it when its WebRTC
/// lists it, which it does where the phone has a hardware H265 decoder; a browser
/// does not, since none has been tried.
class ViewerCodecs {
  const ViewerCodecs._();

  static Future<Set<VideoCodec>>? _asked;

  /// What to publish for this call. [rustWatchGaveOut]: the call's own
  /// connection is showing shares instead, which has no H265 and decodes H264 on
  /// the CPU.
  static Future<Set<VideoCodec>> forCall({
    required bool rustWatchGaveOut,
  }) async => withoutGpu(await _plays, rustWatchGaveOut: rustWatchGaveOut);

  /// Starts asking, at the start of a join, so the answer is in before the
  /// call opens its audio.
  ///
  /// WebRTC answers on the thread that opens the call's output, and a phone
  /// asks from its main thread, which is the UI's. Asked once the room was
  /// up, the question waited behind the output opening (~100 ms on a
  /// Samsung) and the Connecting screen stood still for 160. Asked once per
  /// run and kept, so a later call does not ask again.
  static void askEarly() => unawaited(_plays);

  /// [plays] once the watch connection may have given out. Only Linux and Windows
  /// have one to give out.
  @visibleForTesting
  static Set<VideoCodec> withoutGpu(
    Set<VideoCodec> plays, {
    required bool rustWatchGaveOut,
  }) => rustWatchGaveOut
      ? plays.difference(const {VideoCodec.h264, VideoCodec.h265})
      : plays;

  static Future<Set<VideoCodec>> get _plays => _asked ??= _ask();

  static Future<Set<VideoCodec>> _ask() async {
    final testing = _testOverride();
    if (testing != null) return testing;
    Set<VideoCodec> plays;
    try {
      final capabilities = await getRtpReceiverCapabilities('video');
      plays = fromMimeTypes(
        (capabilities.codecs ?? const []).map((c) => c.mimeType),
      );
    } catch (e) {
      HelperMethods.printDebug('Asking WebRTC what it plays: $e');
      plays = VoiceAttributes.playsUnsaid;
    }
    plays = onDevice(
      plays,
      gpuDecodesOnly: !kIsWeb && (Platform.isLinux || Platform.isWindows),
      gpuPlaysH264: await _rustPlays(watchPlaysH264),
      gpuPlaysH265: await _rustPlays(watchPlaysH265),
      webrtcPlaysH265: !kIsWeb && Platform.isAndroid,
    );
    HelperMethods.printDebug('This device plays ${plays.map((c) => c.name)}');
    return plays;
  }

  static Future<bool> _rustPlays(Future<bool> Function() asked) async {
    if (!RustWatch.available) return false;
    try {
      return await asked();
    } catch (e) {
      HelperMethods.printDebug('Asking whether the GPU decodes a codec: $e');
      return false;
    }
  }

  /// What WebRTC [listed], with what the GPU decodes settled. [gpuDecodesOnly]:
  /// H264 counts only from the GPU on this device. [webrtcPlaysH265]: H265 counts
  /// from WebRTC's list here, which is the phone's own decoder.
  @visibleForTesting
  static Set<VideoCodec> onDevice(
    Set<VideoCodec> listed, {
    required bool gpuDecodesOnly,
    required bool gpuPlaysH264,
    required bool gpuPlaysH265,
    required bool webrtcPlaysH265,
  }) => {
    ...listed.where(
      (c) => switch (c) {
        VideoCodec.h264 => !gpuDecodesOnly,
        VideoCodec.h265 => webrtcPlaysH265,
        _ => true,
      },
    ),
    if (gpuDecodesOnly && gpuPlaysH264) VideoCodec.h264,
    if (gpuPlaysH265) VideoCodec.h265,
  };

  /// `video/VP9` and the like, as WebRTC names them, into codecs. Whether a
  /// listed H265 counts is [onDevice]'s to say. A list that names nothing known
  /// says nothing, so it counts as having said nothing at all.
  static Set<VideoCodec> fromMimeTypes(Iterable<String> mimeTypes) {
    final names = mimeTypes.map((m) => m.split('/').last.toLowerCase()).toSet();
    final plays = {
      if (names.contains('h265')) VideoCodec.h265,
      if (names.contains('h264')) VideoCodec.h264,
      if (names.contains('vp9')) VideoCodec.vp9,
      if (names.contains('vp8')) VideoCodec.vp8,
    };
    return plays.isEmpty ? VoiceAttributes.playsUnsaid : plays;
  }

  /// `RIFT_TEST_PLAYS=vp9,vp8` on a debug build, to drive the rungs no player
  /// to hand lacks. Never in a release.
  static Set<VideoCodec>? _testOverride() {
    if (!kDebugMode || kIsWeb) return null;
    final raw = Platform.environment['RIFT_TEST_PLAYS'];
    return raw == null ? null : VoiceAttributes.playsFromNames(raw.split(','));
  }
}
