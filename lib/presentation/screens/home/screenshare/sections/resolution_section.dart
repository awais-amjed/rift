import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting screen share resolution
class ResolutionSection extends StatelessWidget {
  final int selectedResolution;
  final ValueChanged<int> onChanged;

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
          children: ScreenShareSettings.resolutions
              .map(
                (r) => SettingsChip(
                  label: ScreenShareSettings.labelFor(r),
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
