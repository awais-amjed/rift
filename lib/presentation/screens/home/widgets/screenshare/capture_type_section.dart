import 'package:flutter/material.dart';

import 'settings_chip.dart';
import 'settings_section.dart';

/// Section for selecting capture type (Full Screen or Window)
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
                label: '🖥️ Full Screen',
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
