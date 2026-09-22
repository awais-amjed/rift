import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../sections/audio_source_section.dart';
import '../sections/bitrate_section.dart';
import '../sections/capture_source_section.dart';
import '../sections/capture_type_section.dart';
import '../sections/codec_section.dart';
import '../sections/frame_rate_section.dart';
import '../sections/resolution_section.dart';
import 'audio_toggle.dart';
import 'settings_summary.dart';

/// Every editable screen-share setting, stacked in one scrollable column.
///
/// Purely presentational: it reads [settings] and reports edits back through
/// [onChanged], so the dialog owns the draft and all the loading. The two
/// changes that also trigger a reload — capture type and the audio toggle —
/// get their own callbacks rather than being inferred from a diff.
class ScreenShareSettingsForm extends StatelessWidget {
  final ScreenShareSettings settings;
  final ValueChanged<ScreenShareSettings> onChanged;

  final List<CaptureSource>? captureSources;
  final bool loadingCaptureSources;
  final Map<int, Uint8List> thumbnails;
  final Future<void> Function() onRefreshCaptureSources;

  final List<AudioSource>? audioSources;
  final bool loadingAudioSources;
  final Future<void> Function() onRefreshAudioSources;

  final ValueChanged<bool> onCaptureTypeChanged;
  final VoidCallback onAudioToggle;

  /// What this server allows a share to use, or [ServerLimits.unlimited].
  final int maxShareMbps;

  /// The cap as a [ServerLimits], so the summary resolves the effective
  /// bitrate with exactly the rule the share itself uses.
  ServerLimits get _limits => ServerLimits(maxShareMbps: maxShareMbps);

  const ScreenShareSettingsForm({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.captureSources,
    required this.loadingCaptureSources,
    required this.thumbnails,
    required this.onRefreshCaptureSources,
    required this.audioSources,
    required this.loadingAudioSources,
    required this.onRefreshAudioSources,
    required this.onCaptureTypeChanged,
    required this.onAudioToggle,
    this.maxShareMbps = ServerLimits.unlimited,
  });

  /// Linux picks its capture source through the system portal at capture
  /// time, so the in-app source grid is hidden there.
  bool get _showsSourcePicker => HostPlatform.picksShareSourceInApp;

  /// Full-screen capture takes system audio via loopback; only Linux window
  /// capture needs an explicit PulseAudio source.
  bool get _showsAudioSourcePicker =>
      HostPlatform.picksShareAudioSource &&
      settings.shareAudio &&
      !settings.captureFullScreen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptureTypeSection(
            captureFullScreen: settings.captureFullScreen,
            onChanged: onCaptureTypeChanged,
          ),
          const SizedBox(height: 16),

          if (_showsSourcePicker) ...[
            CaptureSourceSection(
              captureFullScreen: settings.captureFullScreen,
              isLoading: loadingCaptureSources,
              sources: captureSources,
              selectedIndex: settings.selectedVideoSourceIndex,
              thumbnails: thumbnails,
              onChanged: (source) => onChanged(
                settings.copyWith(
                  selectedVideoSourceIndex: source.index,
                  selectedVideoSourcePid: source.audioSourcePid,
                ),
              ),
              onRefresh: onRefreshCaptureSources,
            ),
            const SizedBox(height: 16),
          ],

          ResolutionSection(
            selectedResolution: settings.resolution,
            onChanged: (value) =>
                onChanged(settings.copyWith(resolution: value)),
          ),
          const SizedBox(height: 16),

          FrameRateSection(
            selectedFps: settings.fps,
            onChanged: (value) => onChanged(settings.copyWith(fps: value)),
          ),
          const SizedBox(height: 16),

          BitrateSection(
            selectedBitrate: settings.bitrate,
            maxMbps: maxShareMbps,
            onChanged: (value) => onChanged(settings.copyWith(bitrate: value)),
          ),
          const SizedBox(height: 16),

          CodecSection(
            selectedCodec: settings.codec,
            onChanged: (value) => onChanged(settings.copyWith(codec: value)),
          ),
          const SizedBox(height: 16),

          if (HostPlatform.capturesSystemAudio)
            AudioToggle(
              shareAudio: settings.shareAudio,
              onToggle: onAudioToggle,
            ),

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

          const SizedBox(height: 16),
          SettingsSummary(
            captureFullScreen: settings.captureFullScreen,
            resolution: settings.resolutionLabel,
            fps: settings.fps,
            bitrate: _limits.shareMbps(settings.bitrate),
            shareAudio: settings.shareAudio,
            codec: settings.codec,
          ),
        ],
      ),
    );
  }
}
