import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/noise_filter_work.dart';
import '../../../../../data/enums/noise_suppression.dart';
import '../../../../../logic/services/noise_filter.dart';
import '../../../../common/segmented_control.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'noise_filter_work_line.dart';

/// Which suppressor cleans up the mic, with a line saying what the chosen one
/// suits. Only what this platform has is offered; a saved choice it lacks
/// shows as Standard, which is what it gets. While a choice is still taking
/// effect, the line under it says what it is waiting on.
class NoiseSuppressionChoice extends StatelessWidget {
  final NoiseSuppression value;
  final NoiseFilterWork work;
  final ValueChanged<NoiseSuppression> onChanged;

  const NoiseSuppressionChoice({
    super.key,
    required this.value,
    required this.work,
    required this.onChanged,
  });

  static String _explain(NoiseSuppression mode) => switch (mode) {
    NoiseSuppression.off => 'Best for music, or a mic that is already clean.',
    NoiseSuppression.standard => 'Best for a quiet room.',
    NoiseSuppression.rnnoise => 'Best for fans, keyboards and street noise.',
    NoiseSuppression.dpdfnet => 'Best for a natural voice in a noisy room.',
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
        // A ceiling, not a width: see the sensitive-content choice. Measured
        // per segment, since how many there are depends on the platform and
        // four in the three-segment width cut the longest name short.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: K.settingsChoiceWidth / 3 * choices.length,
          ),
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
        AnimatedSwitcher(
          duration: AppMotion.state,
          switchInCurve: AppMotion.settle,
          switchOutCurve: AppMotion.settle,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: work == NoiseFilterWork.none
              ? Text(
                  _explain(shown),
                  key: ValueKey(shown),
                  style: AppText.secondary.copyWith(color: theme.textTertiary),
                )
              : NoiseFilterWorkLine(key: ValueKey(work), work: work),
        ),
      ],
    );
  }
}
