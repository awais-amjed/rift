import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../sections/capture_source_section.dart';
import '../sections/capture_type_section.dart';
import 'share_options.dart';

/// Every editable screen-share setting: what to share, then how.
///
/// Picking what to share is what the dialog is for, so where the app lists
/// the windows itself the list takes the room there is, and scrolls in it;
/// how it goes out sits below in a compact block. Without a list (Linux,
/// where the system asks at share time) the whole form is one scroll.
///
/// Purely presentational: it reads [settings] and reports edits back through
/// [onChanged], so the dialog owns the draft and all the loading. The changes
/// that also do something else — capture type and the audio toggle reload a
/// list, the advanced settings are remembered at once — get their own
/// callbacks rather than being inferred from a diff.
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
  final ValueChanged<bool> onAdvancedToggled;

  /// What this server allows a share to use, or [ServerLimits.unlimited].
  final int maxShareMbps;

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
    required this.onAdvancedToggled,
    this.maxShareMbps = ServerLimits.unlimited,
  });

  /// The most of the form's height the options below the list may take
  /// before they scroll, so the list always keeps the rest.
  static const _optionsShare = 0.55;

  CaptureSourceSection _sources({required bool fills}) => CaptureSourceSection(
    captureFullScreen: settings.captureFullScreen,
    isLoading: loadingCaptureSources,
    sources: captureSources,
    selectedIndex: settings.selectedVideoSourceIndex,
    thumbnails: thumbnails,
    onChanged: (source) => onChanged(settings.withVideoSource(source)),
    onRefresh: onRefreshCaptureSources,
    fills: fills,
  );

  @override
  Widget build(BuildContext context) {
    final type = CaptureTypeSection(
      captureFullScreen: settings.captureFullScreen,
      onChanged: onCaptureTypeChanged,
    );
    final options = ShareOptions(
      settings: settings,
      onChanged: onChanged,
      maxShareMbps: maxShareMbps,
      audioSources: audioSources,
      loadingAudioSources: loadingAudioSources,
      onRefreshAudioSources: onRefreshAudioSources,
      onAudioToggle: onAudioToggle,
      onAdvancedToggled: onAdvancedToggled,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!HostPlatform.picksShareSourceInApp ||
            !constraints.hasBoundedHeight) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                type,
                const SizedBox(height: 16),
                if (HostPlatform.picksShareSourceInApp) ...[
                  _sources(fills: false),
                  const SizedBox(height: 16),
                ],
                options,
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            type,
            const SizedBox(height: 16),
            Expanded(child: _sources(fills: true)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * _optionsShare,
              ),
              child: SingleChildScrollView(child: options),
            ),
          ],
        );
      },
    );
  }
}
