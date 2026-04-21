import 'package:flutter/material.dart';

import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting screen share resolution
class ResolutionSection extends StatelessWidget {
  final int selectedResolution;
  final ValueChanged<int> onChanged;

  static const _resolutions = [720, 1080, 1440, 2160];
  static const _resolutionLabels = {
    720: '720p',
    1080: '1080p',
    1440: '2K',
    2160: '4K',
  };

  const ResolutionSection({
    super.key,
    required this.selectedResolution,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Resolution',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _resolutions
              .map(
                (r) => SettingsChip(
                  label: _resolutionLabels[r] ?? '${r}p',
                  active: selectedResolution == r,
                  onTap: () => onChanged(r),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
