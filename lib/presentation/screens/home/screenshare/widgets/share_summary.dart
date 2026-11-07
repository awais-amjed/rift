import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/gpu_codecs.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../sections/priority_section.dart';

/// What the share dialog's pages say a share will go out as, in the same terms
/// the share itself decides it.
class ShareSummary {
  const ShareSummary._();

  /// The codec [settings] would go out in, given what the GPU encodes, which
  /// is asked at startup.
  static VideoCodec codecOf(ScreenShareSettings settings) =>
      settings.codecToSend(
        gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
        gpu: GpuCodecs.known,
      );

  /// The bitrate [settings] would go out at, held to the server's limit.
  static int bitrateOf(ScreenShareSettings settings, int maxMbps) =>
      settings.bitrateToSend(
        codec: codecOf(settings),
        limits: ServerLimits(maxShareMbps: maxMbps),
        h264High: HostPlatform.encodesH264OnGpuOnly,
      );

  /// What the Advanced button says is behind it.
  static String advanced(ScreenShareSettings settings, int maxMbps) => [
    PrioritySection.labelFor(settings.priority),
    ScreenShareSettings.nameOf(codecOf(settings)),
    '${bitrateOf(settings, maxMbps)} Mbps',
  ].join(' · ');

  /// What was picked on the page before the list of windows.
  static String quality(ScreenShareSettings settings) => [
    settings.resolutionLabel,
    '${settings.fpsToSend} fps',
    if (HostPlatform.capturesSystemAudio)
      'Sound ${settings.shareAudio ? 'on' : 'off'}',
  ].join(' · ');
}
