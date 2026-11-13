import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/services/phone_share_publish.dart';
import '../../../../../logic/services/web_share_publish.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../sections/bitrate_section.dart';
import '../sections/codec_section.dart';
import '../sections/frame_rate_section.dart';
import '../sections/priority_section.dart';
import '../sections/resolution_section.dart';
import 'advanced_settings.dart';
import 'settings_summary.dart';
import 'share_sound_switch.dart';

/// The options of a share the SDK captures, a phone's or a browser's: the
/// desktop form's sections, stacked for a narrow screen, offering what this
/// device can send ([PhoneShare], [WebShare]). What to share is the system's
/// to ask, and only a browser's share has sound.
///
/// Purely presentational: edits come back through [onChanged].
class SdkShareOptions extends StatelessWidget {
  final ScreenShareSettings settings;
  final List<VideoCodec> codecs;

  /// What Auto sends here: [PhoneShare.autoCodec] or [WebShare.autoCodec].
  final VideoCodec autoCodec;

  /// Whether the share can carry sound: a browser's.
  final bool offersSound;
  final List<int> resolutions;
  final List<int> frameRates;
  final int maxShareMbps;
  final ValueChanged<ScreenShareSettings> onChanged;

  /// The advanced settings were opened or closed.
  final ValueChanged<bool> onAdvancedToggled;

  const SdkShareOptions({
    super.key,
    required this.settings,
    required this.codecs,
    required this.autoCodec,
    this.offersSound = false,
    required this.resolutions,
    required this.frameRates,
    required this.onChanged,
    required this.onAdvancedToggled,
    this.maxShareMbps = ServerLimits.unlimited,
  });

  ServerLimits get _limits => ServerLimits(maxShareMbps: maxShareMbps);

  /// The codec [of] goes out in. One picked and missing here goes back to
  /// Auto.
  VideoCodec _codecOf(ScreenShareSettings of) =>
      of.codecChosen && codecs.contains(of.videoCodec)
      ? of.videoCodec
      : autoCodec;

  int _mbpsOf(ScreenShareSettings of) =>
      of.bitrateToSend(codec: _codecOf(of), limits: _limits);

  @override
  Widget build(BuildContext context) {
    final hint = AppText.secondary.copyWith(color: context.theme.textTertiary);
    final codec = _codecOf(settings);
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
                offered: resolutions,
                onChanged: (value) =>
                    onChanged(settings.copyWith(resolution: value)),
              ),
            ),
            Expanded(
              child: FrameRateSection(
                selectedFps: settings.fps,
                offered: frameRates,
                onChanged: (value) => onChanged(settings.copyWith(fps: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PrioritySection(
          selected: settings.priority,
          onChanged: (value) => onChanged(settings.copyWith(priority: value)),
        ),
        const SizedBox(height: 8),
        Text(PrioritySection.explain(settings.priority), style: hint),
        if (offersSound) ...[
          const SizedBox(height: 8),
          ShareSoundSwitch(
            on: settings.shareAudio,
            onTap: () =>
                onChanged(settings.copyWith(shareAudio: !settings.shareAudio)),
          ),
          if (settings.shareAudio)
            Text('Tick Share audio in the browser\'s picker too.', style: hint),
        ],
        const SizedBox(height: 12),
        AdvancedSettings(
          open: settings.showsAdvanced,
          onToggle: () => onAdvancedToggled(!settings.showsAdvanced),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodecSection(
                chosen: settings.codecChosen ? codec : null,
                auto: autoCodec,
                offered: codecs,
                onChanged: (value) => onChanged(
                  value == null
                      ? settings.copyWith(codecChosen: false)
                      : settings.copyWith(
                          codec: ScreenShareSettings.nameOf(value),
                          codecChosen: true,
                        ),
                ),
              ),
              if (settings.codecChosen) ...[
                const SizedBox(height: 8),
                Text(CodecSection.explain(codec), style: hint),
              ],
              const SizedBox(height: 12),
              BitrateSection(
                chosen: settings.bitrateChosen ? settings.bitrate : null,
                auto: _mbpsOf(settings.copyWith(bitrateChosen: false)),
                maxMbps: maxShareMbps,
                onChanged: (value) => onChanged(
                  value == null
                      ? settings.copyWith(bitrateChosen: false)
                      : settings.copyWith(bitrate: value, bitrateChosen: true),
                ),
              ),
              if (maxShareMbps != ServerLimits.unlimited) ...[
                const SizedBox(height: 4),
                Text(
                  'This server limits screen shares to $maxShareMbps Mbps.',
                  style: hint,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsSummary(
          resolution: ScreenShareSettings.labelFor(settings.resolution),
          fps: settings.fps,
          bitrate: _mbpsOf(settings),
          shareAudio: offersSound && settings.shareAudio,
          codec: ScreenShareSettings.nameOf(codec),
        ),
      ],
    );
  }
}
