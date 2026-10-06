import 'package:flutter/material.dart';

import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// The share's frame rate, as a dropdown.
class FrameRateSection extends StatelessWidget {
  final int selectedFps;

  /// The rates this picture can be sent at
  /// (`ScreenShareSettings.frameRatesAt`): 120 only up to a height.
  final List<int> offered;
  final ValueChanged<int> onChanged;

  const FrameRateSection({
    super.key,
    required this.selectedFps,
    required this.offered,
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
            for (final f in offered)
              AppDropdownOption(value: f, label: '$f fps'),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
