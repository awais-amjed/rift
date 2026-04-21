import 'package:flutter/material.dart';

import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting capture type (Screen or Window)
class CaptureTypeSection extends StatelessWidget {
  final bool captureFullScreen;
  final ValueChanged<bool> onChanged;

  const CaptureTypeSection({
    super.key,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Capture Type',
      children: [
        Row(
          children: [
            Expanded(
              child: SettingsChip(
                label: '🖥️ Screen',
                active: captureFullScreen,
                onTap: () => onChanged(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsChip(
                label: '🪟 Window',
                active: !captureFullScreen,
                onTap: () => onChanged(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
