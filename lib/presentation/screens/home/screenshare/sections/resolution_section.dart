import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// The share's picture height, as a dropdown.
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
        AppDropdown<int>(
          value: selectedResolution,
          options: [
            for (final r in ScreenShareSettings.resolutions)
              AppDropdownOption(
                value: r,
                label: ScreenShareSettings.labelFor(r),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
