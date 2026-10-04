import 'package:flutter/material.dart';

import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// What the share gives up when the computer or the connection cannot keep
/// up, with a line saying what the chosen one means. The names alone do not
/// say when it matters.
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

  static String _explain(SharePriority priority) => switch (priority) {
    SharePriority.smoothness =>
      'When your computer or connection can’t keep up, the picture softens '
          'and the motion stays smooth. Best for games and video.',
    SharePriority.balanced =>
      'When your computer or connection can’t keep up, it gives up a little '
          'sharpness and a few frames.',
    SharePriority.sharpness =>
      'When your computer or connection can’t keep up, frames are dropped '
          'and the picture stays sharp. Best for text and slides.',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Prioritise',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SharePriority.values
              .map(
                (p) => SettingsChip(
                  label: labelFor(p),
                  active: selected == p,
                  onTap: () => onChanged(p),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _explain(selected),
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
      ],
    );
  }
}
