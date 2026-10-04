import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting frame rate (FPS)
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
        Wrap(
          spacing: 8,
          children: ScreenShareSettings.frameRates
              .map(
                (f) => SettingsChip(
                  label: '$f fps',
                  active: selectedFps == f,
                  onTap: () => onChanged(f),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
