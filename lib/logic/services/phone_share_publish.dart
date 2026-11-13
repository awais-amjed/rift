import 'dart:math';
import 'dart:ui' show Size;

import 'package:livekit_client/livekit_client.dart';

import '../../data/classes/screen_share_settings.dart';
import '../../data/classes/server_limits.dart';
import '../../src/rust/api/screenshare/types.dart';

/// How a share the SDK captures, an Android phone's or a browser's, is captured
/// and published.
typedef SdkShareRequest = ({
  VideoPublishOptions publish,
  ScreenShareCaptureOptions capture,
});

/// A capture with its short side at [shortSide], which the patched plugin reads
/// (`third_party/flutter_webrtc/RIFT_PATCHES.md`). A larger one than the screen
/// is the whole screen.
class PhoneShareCapture extends ScreenShareCaptureOptions {
  final int shortSide;

  const PhoneShareCapture({required this.shortSide})
    : super(useiOSBroadcastExtension: false);

  @override
  Map<String, dynamic> toMediaConstraintsMap() => {
    ...super.toMediaConstraintsMap(),
    'riftShortSide': shortSide,
  };
}

/// What an Android phone's share can be, and how a choice goes out
/// (`CALLS.md`, *A phone's share*).
///
/// Everything a phone can send is offered, whatever it does to the phone: how
/// warm it gets is the person's call, and a better phone than the ones tried
/// may not mind at all.
class PhoneShare {
  const PhoneShare._();

  /// What any phone is offered.
  static const _frameRates = [15, 30, 60];

  /// The rate a fast screen is offered as well, and the slowest screen rate
  /// that counts: some report just under a round figure.
  static const _fastFps = 120;
  static const _fastScreenHz = 119.0;

  /// The rates a screen running up to [refreshRate] Hz can be shared at. Above
  /// its own rate there is nothing more to capture.
  static List<int> frameRatesFor(double refreshRate) => [
    ..._frameRates,
    if (refreshRate >= _fastScreenHz) _fastFps,
  ];

  /// What a phone opens on. Its capture sends only what the shared app draws,
  /// so a screen that moves little sends less than this.
  static const defaultFps = 30;

  /// The picture heights offered below a screen's own.
  static const _heights = [360, 480, 720, 1080, 1440, 2160];

  /// Where the screen's size is not known, and the capture takes the whole
  /// screen whatever is asked.
  static const _unknownShortSide = 1080;

  /// A phone's short side is its picture's height, as a landscape desktop's
  /// is, whichever way up the phone is held.
  static int shortSideOf(Size screen) =>
      min(screen.width, screen.height).round();

  /// The heights a screen with this short side can send: its own, and the ones
  /// below it. Nothing above it, which would only be blurrier and larger.
  static List<int> resolutionsFor(int shortSide) {
    final own = shortSide > 0 ? shortSide : _unknownShortSide;
    return [
      for (final height in _heights)
        if (height < own) height,
      own,
    ];
  }

  /// What this phone can encode, in the desktop picker's order, from the mime
  /// types of `getRtpSenderCapabilities`. libwebrtc has no software H264 on
  /// Android, so H264 here means a hardware encoder. VP8 is there on any phone.
  static List<VideoCodec> codecsOf(Iterable<String> encoders) {
    final mimes = encoders.map((mime) => mime.toLowerCase()).toSet();
    return [
      VideoCodec.vp8,
      if (mimes.contains('video/h264')) VideoCodec.h264,
      if (mimes.contains('video/vp9')) VideoCodec.vp9,
    ];
  }

  /// The settings a phone's dialog opens on. Saved ones are kept where this
  /// phone can still send them. Ones no phone has confirmed are a desktop's
  /// defaults, so it opens on the whole screen at [defaultFps] instead.
  static ScreenShareSettings opening(
    ScreenShareSettings saved, {
    required int shortSide,
    required List<int> frameRates,
  }) {
    final heights = resolutionsFor(shortSide);
    if (!saved.phoneSetUp) {
      return saved.copyWith(
        resolution: heights.last,
        fps: defaultFps,
        bitrateChosen: false,
        codecChosen: false,
      );
    }
    return saved.copyWith(
      resolution: heights.contains(saved.resolution)
          ? saved.resolution
          : heights.last,
      fps: frameRates.contains(saved.fps) ? saved.fps : defaultFps,
    );
  }

  /// H264 where the phone has it, for its hardware encoder; otherwise VP8.
  static VideoCodec autoCodec(List<VideoCodec> codecs) =>
      codecs.contains(VideoCodec.h264) ? VideoCodec.h264 : VideoCodec.vp8;

  /// The codec a share goes out in. One picked here and missing on this phone
  /// goes back to Auto.
  static VideoCodec codecToSend(
    ScreenShareSettings settings,
    List<VideoCodec> codecs,
  ) => settings.codecChosen && codecs.contains(settings.videoCodec)
      ? settings.videoCodec
      : autoCodec(codecs);

  /// How [settings] go out.
  ///
  /// The encoding has to be set here. The capture options' parameters do not
  /// reach the encoder: the SDK picks a preset by the capture's width, and for
  /// 1920 that is the 15 fps one.
  static SdkShareRequest request(
    ScreenShareSettings settings, {
    required List<VideoCodec> codecs,
    required ServerLimits limits,
  }) => (
    publish: publishOptions(
      settings,
      codec: codecToSend(settings, codecs),
      limits: limits,
    ),
    capture: PhoneShareCapture(shortSide: settings.resolution),
  );

  /// How a picture the SDK captures goes out in [codec], a phone's or a
  /// browser's.
  ///
  /// One picture, as a desktop's share sends: the SDK's half-size second one
  /// is a second encoder on a phone, for a viewer the first would be too much
  /// for. A backup in another codec, should a viewer need one, sends one too.
  static VideoPublishOptions publishOptions(
    ScreenShareSettings settings, {
    required VideoCodec codec,
    required ServerLimits limits,
  }) {
    final bps =
        settings.bitrateToSend(codec: codec, limits: limits) * 1000 * 1000;
    return VideoPublishOptions(
      videoCodec: codec.name,
      simulcast: false,
      backupVideoCodec: const BackupVideoCodec(simulcast: false),
      screenShareEncoding: VideoEncoding(
        maxBitrate: bps,
        maxFramerate: settings.fps,
      ),
      degradationPreference: switch (settings.priority) {
        SharePriority.smoothness => DegradationPreference.maintainFramerate,
        SharePriority.balanced => DegradationPreference.balanced,
        SharePriority.sharpness => DegradationPreference.maintainResolution,
      },
    );
  }
}
