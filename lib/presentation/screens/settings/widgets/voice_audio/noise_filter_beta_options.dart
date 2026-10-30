import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/noise_filter_priority.dart';
import '../../../../common/app_dropdown.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../setting_toggle_row.dart';

/// Beta options for DPDFNet, for testers to switch mid-call and ask how
/// they sound: where the model runs, and on Windows whether the call holds
/// its 1 ms timer.
class NoiseFilterBetaOptions extends StatelessWidget {
  final List<NoiseFilterPriority> choices;
  final NoiseFilterPriority priority;

  /// Null where there is no such option: off Windows.
  final bool? preciseTiming;
  final ValueChanged<NoiseFilterPriority> onPriorityChanged;
  final ValueChanged<bool> onPreciseTimingChanged;

  const NoiseFilterBetaOptions({
    super.key,
    required this.choices,
    required this.priority,
    required this.preciseTiming,
    required this.onPriorityChanged,
    required this.onPreciseTimingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Beta options',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'For testing: switch them during a call and ask how you sound.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
        const SizedBox(height: 12),
        Text(
          'Noise filter priority',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: K.settingsChoiceWidth),
          child: AppDropdown<NoiseFilterPriority>(
            value: choices.contains(priority)
                ? priority
                : NoiseFilterPriority.normal,
            options: [
              for (final choice in choices)
                AppDropdownOption(value: choice, label: choice.label),
            ],
            onChanged: onPriorityChanged,
          ),
        ),
        if (preciseTiming case final precise?) ...[
          const SizedBox(height: 14),
          SettingToggleRow(
            title: 'Precise timing',
            description: 'Best if your voice crackles or cuts out.',
            value: precise,
            onChanged: onPreciseTimingChanged,
          ),
        ],
      ],
    );
  }
}
