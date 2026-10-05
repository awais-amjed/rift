import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// The share's frame rate, as a dropdown.
class FrameRateSection extends StatelessWidget {
  final int selectedFps;
  final ValueChanged<int> onChanged;

  const FrameRateSection({
    super.key,
    required this.selectedFps,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Frame rate',
      children: [
        AppDropdown<int>(
          value: selectedFps,
          options: [
            for (final f in ScreenShareSettings.frameRates)
              AppDropdownOption(value: f, label: '$f fps'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
