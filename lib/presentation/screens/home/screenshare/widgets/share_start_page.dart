import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/services/host_platform.dart';
import 'settings_section.dart';
import 'share_advanced_button.dart';
import 'share_dialog_header.dart';
import 'share_kind_card.dart';
import 'share_quality_row.dart';
import 'share_sound_switch.dart';
import 'share_summary.dart';

/// What the share dialog opens on: what to share, as two big cards, and only as
/// much about how as most shares need. The rest is behind Advanced.
class ShareStartPage extends StatelessWidget {
  final ScreenShareSettings settings;
  final int maxShareMbps;
  final ValueChanged<ScreenShareSettings> onChanged;

  /// A card was pressed: true for an entire screen. Null while one is being
  /// answered.
  final ValueChanged<bool>? onKindPicked;
  final VoidCallback onAudioToggle;
  final VoidCallback onAdvanced;
  final VoidCallback onClose;

  /// A running share is being switched to another source: only what to
  /// share is asked, since its quality is changed from its own menu.
  final bool switching;

  const ShareStartPage({
    super.key,
    required this.settings,
    required this.maxShareMbps,
    required this.onChanged,
    required this.onKindPicked,
    required this.onAudioToggle,
    required this.onAdvanced,
    required this.onClose,
    this.switching = false,
  });

  static const _sideBySideWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    final picked = onKindPicked;
    final sound = HostPlatform.capturesSystemAudio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 20,
      children: [
        ShareDialogHeader(
          title: switching ? 'Switch to' : 'Share your screen',
          onClose: onClose,
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 20,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: ShareKindCard(
                        icon: Icons.desktop_windows_outlined,
                        label: 'Entire screen',
                        onTap: picked == null ? null : () => picked(true),
                      ),
                    ),
                    Expanded(
                      child: ShareKindCard(
                        icon: Icons.web_asset,
                        label: 'A window',
                        onTap: picked == null ? null : () => picked(false),
                      ),
                    ),
                  ],
                ),
                if (!switching) ...[
                  SettingsSection(
                    label: 'Quality',
                    children: [
                      ShareQualityRow(
                        settings: settings,
                        onChanged: onChanged,
                        onCustom: onAdvanced,
                      ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final advanced = ShareAdvancedButton(
                        summary: ShareSummary.advanced(settings, maxShareMbps),
                        onTap: onAdvanced,
                      );
                      final soundSwitch = ShareSoundSwitch(
                        on: settings.shareAudio,
                        onTap: onAudioToggle,
                      );
                      // Side by side the summary would be cut to nothing.
                      if (constraints.maxWidth < _sideBySideWidth) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [if (sound) soundSwitch, advanced],
                        );
                      }
                      return Row(
                        mainAxisAlignment: sound
                            ? MainAxisAlignment.spaceBetween
                            : MainAxisAlignment.end,
                        spacing: 8,
                        children: [
                          if (sound) soundSwitch,
                          Flexible(child: advanced),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
