import 'package:livekit_client/livekit_client.dart';

/// How an Android phone publishes its screen.
///
/// In H264 at 30 fps where the phone offers an H264 encoder, which on Android
/// is a hardware one, since libwebrtc has no software H264 there. Without one,
/// null: the SDK's own VP8 at 15 fps, as a phone has always shared
/// (`CALLS.md`, *A phone's share*).
///
/// [encoders] is the mime types of `getRtpSenderCapabilities`. It is asked first
/// because libwebrtc does not fall back by itself.
///
/// The encoding has to be set here. The capture options' parameters do not
/// reach the encoder: the SDK picks a preset by the capture's width, and for
/// 1920 that is the 15 fps one.
VideoPublishOptions? phoneSharePublishOptions(Iterable<String> encoders) {
  final hasH264 = encoders.any((mime) => mime.toLowerCase() == 'video/h264');
  if (!hasH264) return null;
  return VideoPublishOptions(
    videoCodec: 'h264',
    screenShareEncoding: VideoParametersPresets.screenShareH1080FPS30.encoding,
  );
}
