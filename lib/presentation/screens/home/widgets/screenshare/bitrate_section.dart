import 'package:flutter/material.dart';

import 'settings_chip.dart';
import 'settings_section.dart';

/// Section for selecting video bitrate
class BitrateSection extends StatelessWidget {
  final int selectedBitrate;
  final ValueChanged<int> onChanged;

  static const _bitrateOptions = [2, 4, 6, 8, 10, 12, 14, 15];

  const BitrateSection({
    super.key,
    required this.selectedBitrate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Bitrate',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _bitrateOptions
              .map(
                (b) => SettingsChip(
                  label: '$b Mbps',
                  active: selectedBitrate == b,
                  onTap: () => onChanged(b),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
