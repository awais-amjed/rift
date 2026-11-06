import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/gpu_codecs.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_button.dart';
import '../../../../common/checkbox_row.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../sections/audio_source_section.dart';
import '../sections/priority_section.dart';
import 'settings_section.dart';
import 'share_bitrate_choices.dart';
import 'share_choice_button.dart';
import 'share_choice_grid.dart';
import 'share_dialog_header.dart';
import 'share_summary.dart';

/// Over the widget budget and one job: the rows of one page.
///
/// The share's settings that most shares never need, each row a selection so
/// all of its options can be seen at once. The sound's apps stay a dropdown,
/// their list being different every time.
///
/// Reached before anybody has said what they will share, so what it shows
/// about sound cannot depend on that: both a whole screen's choice and the
/// window's are here, and each says which it is for.
class ShareAdvancedPage extends StatelessWidget {
  final ScreenShareSettings settings;
  final int maxShareMbps;
  final ValueChanged<ScreenShareSettings> onChanged;

  final List<AudioSource>? audioSources;
  final bool loadingAudioSources;
  final Future<void> Function() onRefreshAudioSources;

  final VoidCallback onDone;

  const ShareAdvancedPage({
    super.key,
    required this.settings,
    required this.maxShareMbps,
    required this.onChanged,
    required this.audioSources,
    required this.loadingAudioSources,
    required this.onRefreshAudioSources,
    required this.onDone,
  });

  /// Where a window's sound is picked after the window, this choice is only
  /// a whole screen's; elsewhere on Linux it is every share's.
  static String get _soundLabel =>
      HostPlatform.matchesWindowSound ? 'Sound with an entire screen' : 'Sound';

  /// A window's sound may be one remembered for its app, which this asks about
  /// again.
  bool get _offersChoosingSound =>
      HostPlatform.matchesWindowSound &&
      settings.shareAudio &&
      settings.soundForApps.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        ShareDialogHeader(title: 'Advanced', onBack: onDone),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                _priority(context),
                _resolution(),
                _frameRate(),
                _codec(),
                _bitrate(context),
                if (HostPlatform.picksShareAudioSource && settings.shareAudio)
                  AudioSourceSection(
                    label: _soundLabel,
                    audioSources: audioSources,
                    selectedAudioSource: settings.selectedAudioSource,
                    isLoading: loadingAudioSources,
                    onChanged: (source) => onChanged(
                      source == null
                          ? settings.copyWith(clearAudioSource: true)
                          : settings.copyWith(selectedAudioSource: source),
                    ),
                    onRefresh: onRefreshAudioSources,
                  ),
                if (_offersChoosingSound)
                  CheckboxRow(
                    label: 'Choose a window’s sound this time',
                    value: settings.choosesSoundThisTime,
                    onChanged: (value) => onChanged(
                      settings.copyWith(choosesSoundThisTime: value),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(label: 'Done', onPressed: onDone),
        ),
      ],
    );
  }

  Widget _priority(BuildContext context) => SettingsSection(
    label: 'Prioritise',
    children: [
      ShareChoiceGrid(
        columns: SharePriority.values.length,
        minWidth: 88,
        children: [
          for (final priority in SharePriority.values)
            ShareChoiceButton(
              label: PrioritySection.labelFor(priority),
              selected: priority == settings.priority,
              onTap: () => onChanged(settings.copyWith(priority: priority)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _hint(context, PrioritySection.explain(settings.priority)),
    ],
  );

  Widget _resolution() => SettingsSection(
    label: 'Resolution',
    children: [
      ShareChoiceGrid(
        columns: ScreenShareSettings.resolutions.length,
        children: [
          for (final height in ScreenShareSettings.resolutions)
            ShareChoiceButton(
              label: ScreenShareSettings.labelFor(height),
              selected: height == settings.resolution,
              onTap: () => onChanged(settings.copyWith(resolution: height)),
            ),
        ],
      ),
    ],
  );

  Widget _frameRate() {
    final offered = ScreenShareSettings.frameRatesAt(settings.resolution);
    return SettingsSection(
      label: 'Frame rate',
      children: [
        ShareChoiceGrid(
          columns: ScreenShareSettings.frameRates.length,
          children: [
            for (final fps in ScreenShareSettings.frameRates)
              ShareChoiceButton(
                label: '$fps fps',
                selected: fps == settings.fpsToSend,
                onTap: offered.contains(fps)
                    ? () => onChanged(settings.copyWith(fps: fps))
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _codec() {
    final offered = ScreenShareSettings.codecsOffered(
      gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
      gpu: GpuCodecs.known,
    );
    // What goes out, not what is stored: a hand-picked H264 with no GPU to
    // encode it goes out as VP9, and H264 is not offered then.
    final chosen = settings.codecChosen ? ShareSummary.codecOf(settings) : null;
    final auto = ShareSummary.codecOf(settings.copyWith(codecChosen: false));
    return SettingsSection(
      label: 'Codec',
      children: [
        ShareChoiceGrid(
          columns: offered.length + 1,
          children: [
            ShareChoiceButton(
              label: 'Auto',
              sub: ScreenShareSettings.nameOf(auto),
              selected: chosen == null,
              onTap: () => onChanged(settings.copyWith(codecChosen: false)),
            ),
            for (final codec in offered)
              ShareChoiceButton(
                label: ScreenShareSettings.nameOf(codec),
                selected: codec == chosen,
                onTap: () => onChanged(
                  settings.copyWith(
                    codec: ScreenShareSettings.nameOf(codec),
                    codecChosen: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bitrate(BuildContext context) => SettingsSection(
    label: 'Bitrate',
    children: [
      ShareBitrateChoices(
        chosen: settings.bitrateChosen ? settings.bitrate : null,
        auto: ShareSummary.bitrateOf(
          settings.copyWith(bitrateChosen: false),
          maxShareMbps,
        ),
        maxMbps: maxShareMbps,
        onChanged: (value) => onChanged(
          value == null
              ? settings.copyWith(bitrateChosen: false)
              : settings.copyWith(bitrate: value, bitrateChosen: true),
        ),
      ),
      if (maxShareMbps != ServerLimits.unlimited) ...[
        const SizedBox(height: 8),
        _hint(
          context,
          'This server limits screen shares to $maxShareMbps Mbps.',
        ),
      ],
    ],
  );

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: AppText.secondary.copyWith(color: context.theme.textTertiary),
  );
}
