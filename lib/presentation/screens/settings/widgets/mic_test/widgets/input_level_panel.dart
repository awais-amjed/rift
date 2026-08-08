import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';
import 'mic_level_meter.dart';

/// The input-level meter with the wording that says what it is for.
///
/// It used to be an "Input Sensitivity" panel: the same meter with a threshold
/// marker on it and a slider underneath, feeding a noise gate. The gate could
/// not be made to work, so what is left is the meter as a plain "is my
/// microphone being heard, and how loudly" readout.
class InputLevelPanel extends StatelessWidget {
  /// The current microphone level, 0–1 on `PcmLevel`'s scale.
  final double level;

  /// Whether a mic test is running, which is what makes the meter live.
  final bool testing;

  final ThemeState themeState;

  const InputLevelPanel({
    super.key,
    required this.level,
    required this.testing,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Input Level',
          style: AppText.row.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Test Mic and speak — the bar should move with your voice. If it '
          'stays dark, Rift is not hearing the input device selected above.',
          style: AppText.secondary.copyWith(
            color: themeState.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        MicLevelMeter(level: level, active: testing, themeState: themeState),
      ],
    );
  }
}
