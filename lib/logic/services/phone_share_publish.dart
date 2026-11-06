import 'dart:math';
import 'dart:ui' show Size;

import 'package:livekit_client/livekit_client.dart';

import '../../data/classes/screen_share_settings.dart';
import '../../data/classes/server_limits.dart';
import '../../data/classes/share_encoding.dart';
import '../../src/rust/api/screenshare/types.dart';

/// How an Android phone's share is captured and published.
typedef PhoneShareRequest = ({
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

  /// Android's capture gives no more than 60 a second, so 120 is not offered.
  static const frameRates = [15, 30, 60];

  /// What a phone opens on. Its capture sends only what the shared app draws,
  /// so a screen that moves little sends less than this.
  static const defaultFps = 30;

  /// The picture heights offered below a screen's own.
  static const _heights = [480, 720, 1080, 1440, 2160];

  /// Where the screen's size is not known, and the capture takes the whole
  /// screen whatever is asked.
  static const _unknownShortSide = 1080;

  /// The second, half-size picture the SDK sends beside the first takes a
  /// quarter of its bitrate, so the two are this many times the first. VP9
  /// sends one picture.
  static const _simulcastTotal = 1.25;

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

  /// What Auto caps a phone's picture at, in Mbps: half of what a desktop's
  /// H264 asks for. A phone usually uploads over less, and 1080p at 30 fps comes
  /// to 5, measured as clean on a phone's share. It is the same in every codec:
  /// a desktop's VP9 is given less for being tighter, which a phone's real-time
  /// encoder cannot count on, and 720p at 60 fps in VP9 came to 2.
  static int autoMbps({required int resolution, required int fps}) => max(
    2,
    ShareEncoding.autoMbps(
          resolution: resolution,
          fps: fps,
          codec: VideoCodec.h264,
        ) ~/
        2,
  );

  /// The first picture's bitrate, the one the dialog names, in Mbps.
  static int mbpsToSend(
    ScreenShareSettings settings, {
    required ServerLimits limits,
  }) => limits.shareMbps(
    settings.bitrateChosen
        ? settings.bitrate
        : autoMbps(resolution: settings.resolution, fps: settings.fps),
  );

  /// How [settings] go out.
  ///
  /// The encoding has to be set here. The capture options' parameters do not
  /// reach the encoder: the SDK picks a preset by the capture's width, and for
  /// 1920 that is the 15 fps one.
  ///
  /// A server's limit holds everything the share sends, so where it would
  /// bind, the first picture leaves room for the second.
  static PhoneShareRequest request(
    ScreenShareSettings settings, {
    required List<VideoCodec> codecs,
    required ServerLimits limits,
  }) {
    final codec = codecToSend(settings, codecs);
    var bps = mbpsToSend(settings, limits: limits) * 1000 * 1000;
    if (limits.maxShareMbps != ServerLimits.unlimited &&
        codec != VideoCodec.vp9) {
      final room = limits.maxShareMbps * 1000 * 1000 ~/ _simulcastTotal;
      bps = min(bps, room);
    }
    return (
      publish: VideoPublishOptions(
        videoCodec: codec.name,
        screenShareEncoding: VideoEncoding(
          maxBitrate: bps,
          maxFramerate: settings.fps,
        ),
        degradationPreference: switch (settings.priority) {
          SharePriority.smoothness => DegradationPreference.maintainFramerate,
          SharePriority.balanced => DegradationPreference.balanced,
          SharePriority.sharpness => DegradationPreference.maintainResolution,
        },
      ),
      capture: PhoneShareCapture(shortSide: settings.resolution),
    );
  }
}
