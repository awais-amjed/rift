import 'package:flutter/material.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting video bitrate.
///
/// [maxMbps] is what this server allows, or [ServerLimits.unlimited] when it
/// allows anything (migration 028). A share goes out at full rate to every
/// watcher with nothing downscaling in between, so an operator may well have
/// set one — and the picker has to say so, because the alternative is
/// offering 15 Mbps, accepting it, and publishing at 3 without a word.
class BitrateSection extends StatelessWidget {
  final int selectedBitrate;
  final int maxMbps;
  final ValueChanged<int> onChanged;

  /// The ladder everyone sees when nothing is capped.
  static const bitrateOptions = [2, 4, 6, 8, 10, 12, 14, 15];

  const BitrateSection({
    super.key,
    required this.selectedBitrate,
    required this.onChanged,
    this.maxMbps = ServerLimits.unlimited,
  });

  /// The chips to draw, which is the ladder plus the cap itself when the cap
  /// is not already a rung.
  ///
  /// Without that extra rung a server allowing 3 Mbps would light the 2 and
  /// publish 3, because the share is clamped to the cap
  /// ([ServerLimits.shareMbps]) and not snapped to the nearest option below
  /// it. A picker that disagrees with what is sent is worse than no picker.
  ///
  /// The rungs above the cap stay on screen, greyed. Dropping them would
  /// leave a short row with nothing to explain itself.
  static List<int> optionsFor(int maxMbps) {
    if (maxMbps == ServerLimits.unlimited ||
        bitrateOptions.contains(maxMbps) ||
        maxMbps > bitrateOptions.last) {
      return bitrateOptions;
    }
    return [...bitrateOptions, maxMbps]..sort();
  }

  /// What will actually be published — the same rule the share itself uses,
  /// so the lit chip and the stream agree.
  ///
  /// The stored setting is left alone when it is above the cap: it is the
  /// right answer again on a server that allows it.
  static int effectiveFor(int selected, int maxMbps) =>
      ServerLimits(maxShareMbps: maxMbps).shareMbps(selected);

  bool _allowed(int mbps) =>
      maxMbps == ServerLimits.unlimited || mbps <= maxMbps;

  @override
  Widget build(BuildContext context) {
    final effective = effectiveFor(selectedBitrate, maxMbps);
    return SettingsSection(
      label: 'Bitrate',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: optionsFor(maxMbps)
              .map(
                (b) => SettingsChip(
                  label: '$b Mbps',
                  active: effective == b,
                  enabled: _allowed(b),
                  onTap: () => onChanged(b),
                ),
              )
              .toList(),
        ),
        if (maxMbps != ServerLimits.unlimited) ...[
          const SizedBox(height: 8),
          Text(
            'This server limits screen shares to $maxMbps Mbps. A share goes '
            'out at full quality to everyone watching, so the cost is one '
            'share times the number of people looking at it.',
            style: AppText.secondary.copyWith(
              color: context.theme.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
