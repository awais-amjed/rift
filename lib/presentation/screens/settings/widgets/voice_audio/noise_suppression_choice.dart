import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/noise_suppression.dart';
import '../../../../../logic/services/noise_filter.dart';
import '../../../../common/segmented_control.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Which suppressor cleans up the mic, with a line saying what the chosen one
/// suits. Only what this platform has is offered; a saved choice it lacks
/// shows as Standard, which is what it gets.
class NoiseSuppressionChoice extends StatelessWidget {
  final NoiseSuppression value;
  final ValueChanged<NoiseSuppression> onChanged;

  const NoiseSuppressionChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static String _explain(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.off => 'Best for music, or a mic that is already clean.',
    NoiseSuppression.standard => 'Best for a quiet room.',
    NoiseSuppression.rnnoise => 'Best for fans, keyboards and street noise.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final choices = NoiseFilter.choices;
    final shown = choices.contains(value) ? value : NoiseSuppression.standard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Noise suppression',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 8),
        // A ceiling, not a width: see the sensitive-content choice.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: K.settingsChoiceWidth),
          child: SegmentedControl<NoiseSuppression>(
            value: shown,
            onChanged: onChanged,
            options: [
              for (final mode in choices)
                SegmentOption(value: mode, label: mode.label),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _explain(shown),
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
