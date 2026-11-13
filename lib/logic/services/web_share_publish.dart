import 'package:livekit_client/livekit_client.dart';

import '../../data/classes/screen_share_settings.dart';
import '../../data/classes/server_limits.dart';
import '../../src/rust/api/screenshare/types.dart';
import 'phone_share_publish.dart';

/// A browser's capture, asked for at most [height] pixels tall and [fps]
/// frames a second, with the picture's sound when [captureScreenAudio].
///
/// Maxima, not sizes: the browser scales a larger screen down, keeping its
/// shape, and never blows a smaller one up. The SDK's own constraints ask for
/// a 16:9 size, which an ultrawide screen does not have.
class WebShareCapture extends ScreenShareCaptureOptions {
  final int height;
  final int fps;

  WebShareCapture({
    required this.height,
    required this.fps,
    required bool sound,
  }) : super(
         captureScreenAudio: sound,
         maxFrameRate: fps.toDouble(),
         params: VideoParameters(
           dimensions: VideoDimensions(height * 16 ~/ 9, height),
         ),
       );

  /// The SDK copies the options to ask for sound
  /// (`createScreenShareTracksWithAudio`), and its own copy is a plain
  /// [ScreenShareCaptureOptions]: a share with sound lost the constraints
  /// below and went out at the SDK's 30 fps whatever was chosen.
  @override
  WebShareCapture copyWith({
    bool? useiOSBroadcastExtension,
    bool? captureScreenAudio,
    VideoParameters? params,
    String? sourceId,
    double? maxFrameRate,
    bool? preferCurrentTab,
    String? selfBrowserSurface,
  }) => WebShareCapture(
    height: height,
    fps: fps,
    sound: captureScreenAudio ?? this.captureScreenAudio,
  );

  @override
  Map<String, dynamic> toMediaConstraintsMap() => {
    'height': {'max': height},
    'frameRate': {'ideal': fps, 'max': fps},
  };
}

/// What a browser's share can be, and how a choice goes out (`CALLS.md`,
/// *A browser's share*). What to share is the browser's picker's to ask.
class WebShare {
  const WebShare._();

  /// The picture heights offered. The browser sends no more than the shared
  /// screen has, whatever is asked.
  static const resolutions = [480, 720, 1080, 1440, 2160];

  /// A browser captures a screen at up to 60.
  static const frameRates = [15, 30, 60];

  static const defaultResolution = 1080;
  static const defaultFps = 30;

  /// The settings the dialog opens on. Ones this browser never confirmed are
  /// a desktop's defaults, which ask more than most browsers keep up with.
  static ScreenShareSettings opening(ScreenShareSettings saved) {
    if (!saved.phoneSetUp) {
      return saved.copyWith(
        resolution: defaultResolution,
        fps: defaultFps,
        bitrateChosen: false,
        codecChosen: false,
        shareAudio: true,
      );
    }
    return saved.copyWith(
      resolution: resolutions.contains(saved.resolution)
          ? saved.resolution
          : defaultResolution,
      fps: frameRates.contains(saved.fps) ? saved.fps : defaultFps,
    );
  }

  /// VP8: what a browser's share always went out in, which every viewer
  /// decodes. The others are there to pick.
  static const autoCodec = VideoCodec.vp8;

  /// The codec a share goes out in. One picked here and missing in this
  /// browser goes back to Auto.
  static VideoCodec codecToSend(
    ScreenShareSettings settings,
    List<VideoCodec> codecs,
  ) => settings.codecChosen && codecs.contains(settings.videoCodec)
      ? settings.videoCodec
      : autoCodec;

  /// How [settings] go out.
  static SdkShareRequest request(
    ScreenShareSettings settings, {
    required List<VideoCodec> codecs,
    required ServerLimits limits,
  }) => (
    publish: PhoneShare.publishOptions(
      settings,
      codec: codecToSend(settings, codecs),
      limits: limits,
    ),
    capture: WebShareCapture(
      height: settings.resolution,
      fps: settings.fps,
      sound: settings.shareAudio,
    ),
  );
}
