import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/gpu_codecs.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../sections/audio_source_section.dart';
import '../sections/bitrate_section.dart';
import '../sections/codec_section.dart';
import '../sections/frame_rate_section.dart';
import '../sections/priority_section.dart';
import '../sections/resolution_section.dart';
import 'advanced_settings.dart';
import 'audio_toggle.dart';
import 'settings_summary.dart';

/// How a share goes out: its quality in one row, its sound, the advanced
/// settings behind a row that opens them, and a summary of all of it.
///
/// Purely presentational, like the form it sits in: edits come back through
/// [onChanged].
class ShareOptions extends StatelessWidget {
  final ScreenShareSettings settings;
  final ValueChanged<ScreenShareSettings> onChanged;

  /// What this server allows a share to use, or [ServerLimits.unlimited].
  final int maxShareMbps;

  final List<AudioSource>? audioSources;
  final bool loadingAudioSources;
  final Future<void> Function() onRefreshAudioSources;
  final VoidCallback onAudioToggle;

  /// The advanced settings were opened or closed.
  final ValueChanged<bool> onAdvancedToggled;

  const ShareOptions({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.maxShareMbps,
    required this.audioSources,
    required this.loadingAudioSources,
    required this.onRefreshAudioSources,
    required this.onAudioToggle,
    required this.onAdvancedToggled,
  });

  /// Linux shares one application's sound, screen or window; elsewhere a
  /// whole screen takes the system's sound and a window its own app's.
  bool get _showsAudioSourcePicker =>
      HostPlatform.picksShareAudioSource && settings.shareAudio;

  /// The codec [of] would go out in, given what the GPU encodes, which is
  /// asked at startup.
  static VideoCodec _codecOf(ScreenShareSettings of) => of.codecToSend(
    gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
    gpu: GpuCodecs.known,
  );

  VideoCodec get _codec => _codecOf(settings);

  int _bitrateOf(ScreenShareSettings of) => of.bitrateToSend(
    codec: _codecOf(of),
    limits: ServerLimits(maxShareMbps: maxShareMbps),
  );

  int get _bitrate => _bitrateOf(settings);

  @override
  Widget build(BuildContext context) {
    final hint = AppText.secondary.copyWith(color: context.theme.textTertiary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: ResolutionSection(
                selectedResolution: settings.resolution,
                onChanged: (value) =>
                    onChanged(settings.copyWith(resolution: value)),
              ),
            ),
            Expanded(
              child: FrameRateSection(
                selectedFps: settings.fpsToSend,
                offered: ScreenShareSettings.frameRatesAt(settings.resolution),
                onChanged: (value) => onChanged(settings.copyWith(fps: value)),
              ),
            ),
            Expanded(
              child: PrioritySection(
                selected: settings.priority,
                onChanged: (value) =>
                    onChanged(settings.copyWith(priority: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(PrioritySection.explain(settings.priority), style: hint),
        if (HostPlatform.capturesSystemAudio) ...[
          const SizedBox(height: 16),
          AudioToggle(shareAudio: settings.shareAudio, onToggle: onAudioToggle),
        ],
        if (_showsAudioSourcePicker) ...[
          const SizedBox(height: 16),
          AudioSourceSection(
            audioSources: audioSources,
            selectedAudioSource: settings.selectedAudioSource,
            isLoading: loadingAudioSources,
            onChanged: (source) =>
                onChanged(settings.copyWith(selectedAudioSource: source)),
            onRefresh: onRefreshAudioSources,
          ),
        ],
        const SizedBox(height: 12),
        AdvancedSettings(
          open: settings.showsAdvanced,
          onToggle: () => onAdvancedToggled(!settings.showsAdvanced),
          child: _advanced(hint),
        ),
        const SizedBox(height: 12),
        SettingsSummary(
          captureFullScreen: settings.captureFullScreen,
          resolution: settings.resolutionLabel,
          fps: settings.fpsToSend,
          bitrate: _bitrate,
          shareAudio: settings.shareAudio,
          codec: ScreenShareSettings.nameOf(_codec),
        ),
      ],
    );
  }

  Widget _advanced(TextStyle hint) {
    final codec = _codec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: CodecSection(
                chosen: settings.codecChosen ? settings.videoCodec : null,
                auto: _codecOf(settings.copyWith(codecChosen: false)),
                offered: ScreenShareSettings.codecsOffered(
                  gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
                  gpu: GpuCodecs.known,
                ),
                onChanged: (value) => onChanged(
                  value == null
                      ? settings.copyWith(codecChosen: false)
                      : settings.copyWith(
                          codec: ScreenShareSettings.nameOf(value),
                          codecChosen: true,
                        ),
                ),
              ),
            ),
            Expanded(
              child: BitrateSection(
                chosen: settings.bitrateChosen ? settings.bitrate : null,
                auto: _bitrateOf(settings.copyWith(bitrateChosen: false)),
                maxMbps: maxShareMbps,
                onChanged: (value) => onChanged(
                  value == null
                      ? settings.copyWith(bitrateChosen: false)
                      : settings.copyWith(bitrate: value, bitrateChosen: true),
                ),
              ),
            ),
          ],
        ),
        // Auto's pick follows the priority, whose own line already says
        // what it is best for; a second line about the codec would argue
        // with it.
        if (settings.codecChosen) ...[
          const SizedBox(height: 8),
          Text(CodecSection.explain(codec), style: hint),
        ],
        if (maxShareMbps != ServerLimits.unlimited) ...[
          const SizedBox(height: 4),
          Text(
            'This server limits screen shares to $maxShareMbps Mbps.',
            style: hint,
          ),
        ],
      ],
    );
  }
}
