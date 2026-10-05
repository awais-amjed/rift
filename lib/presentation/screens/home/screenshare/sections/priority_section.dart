import 'package:flutter/material.dart';

import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// What the share gives up when the computer or the connection cannot keep
/// up, as a dropdown.
class PrioritySection extends StatelessWidget {
  final SharePriority selected;
  final ValueChanged<SharePriority> onChanged;

  const PrioritySection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static String labelFor(SharePriority priority) => switch (priority) {
    SharePriority.smoothness => 'Smoothness',
    SharePriority.balanced => 'Balanced',
    SharePriority.sharpness => 'Sharpness',
  };

  /// What the chosen priority is best for, shown under the quality row.
  static String explain(SharePriority priority) => switch (priority) {
    SharePriority.smoothness => 'Smoothness is best for games and video.',
    SharePriority.balanced => 'Balanced is best for a mix of motion and text.',
    SharePriority.sharpness => 'Sharpness is best for text, code and slides.',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Prioritise',
      children: [
        AppDropdown<SharePriority>(
          value: selected,
          options: [
            for (final p in SharePriority.values)
              AppDropdownOption(value: p, label: labelFor(p)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
