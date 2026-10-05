import 'package:flutter/material.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// The share's bitrate, as a dropdown led by Auto.
///
/// [maxMbps] is what this server allows, or [ServerLimits.unlimited] when it
/// allows anything. A share goes out at full rate to every watcher with
/// nothing downscaling in between, so an operator may well have set one, and
/// the picker has to agree with it: the alternative is offering 15 Mbps,
/// accepting it, and publishing at 3 without a word.
class BitrateSection extends StatelessWidget {
  /// The bitrate picked by hand, or null for Auto.
  final int? chosen;

  /// What Auto sends for this picture, already held to [maxMbps].
  final int auto;
  final int maxMbps;

  /// Null is Auto.
  final ValueChanged<int?> onChanged;

  /// The ladder everyone sees when nothing is capped.
  static const bitrateOptions = [2, 4, 6, 8, 10, 12, 14, 15];

  const BitrateSection({
    super.key,
    required this.chosen,
    required this.auto,
    required this.onChanged,
    this.maxMbps = ServerLimits.unlimited,
  });

  /// The ladder, plus the cap itself when the cap is not already a rung.
  ///
  /// Without that extra rung a server allowing 3 Mbps would show 2 and
  /// publish 3, because the share is clamped to the cap
  /// ([ServerLimits.shareMbps]) and not snapped to the nearest option below
  /// it. A picker that disagrees with what is sent is worse than no picker.
  static List<int> optionsFor(int maxMbps) {
    if (maxMbps == ServerLimits.unlimited ||
        bitrateOptions.contains(maxMbps) ||
        maxMbps > bitrateOptions.last) {
      return bitrateOptions;
    }
    return [...bitrateOptions, maxMbps]..sort();
  }

  /// What will actually be published — the same rule the share itself uses,
  /// so the shown choice and the stream agree.
  ///
  /// The stored setting is left alone when it is above the cap: it is the
  /// right answer again on a server that allows it.
  static int effectiveFor(int selected, int maxMbps) =>
      ServerLimits(maxShareMbps: maxMbps).shareMbps(selected);

  bool _allowed(int mbps) =>
      maxMbps == ServerLimits.unlimited || mbps <= maxMbps;

  @override
  Widget build(BuildContext context) {
    final picked = chosen;
    return SettingsSection(
      label: 'Bitrate',
      children: [
        AppDropdown<int?>(
          value: picked == null ? null : effectiveFor(picked, maxMbps),
          options: [
            AppDropdownOption(value: null, label: 'Auto ($auto Mbps)'),
            // Above the cap would be sent at the cap, so it is not offered.
            for (final b in optionsFor(maxMbps))
              if (_allowed(b)) AppDropdownOption(value: b, label: '$b Mbps'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
