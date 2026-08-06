import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/services/mic_level_scale.dart';
import '../../../../../theme/app_text.dart';

/// The noise-gate threshold control: how loud the mic must be before Rift
/// transmits at all.
///
/// Drawn on [MicLevelScale] rather than on the raw level the gate compares
/// against — see that class for why a straight 0–1 slider was mostly a mute
/// switch. The percentage shown is slider travel, which is what the reader is
/// actually moving; the raw level it maps to is an implementation detail and
/// would only ever read as a confusingly small number.
class InputSensitivitySlider extends StatelessWidget {
  /// The stored gate threshold, in raw analyser units.
  final double threshold;

  /// Receives the new threshold, already converted back to raw units.
  final ValueChanged<double> onChanged;

  final ThemeState themeState;

  const InputSensitivitySlider({
    super.key,
    required this.threshold,
    required this.onChanged,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    final position = MicLevelScale.toPosition(threshold);

    return Row(
      children: [
        Text(
          'Threshold',
          style: AppText.secondary.copyWith(
            color: themeState.textSecondary,
            fontSize: 12,
          ),
        ),
        Expanded(
          child: Slider(
            value: position,
            onChanged: (value) => onChanged(MicLevelScale.toLevel(value)),
            activeColor: themeState.primary,
            inactiveColor: themeState.bgActive,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            threshold <= 0 ? 'Off' : '${(position * 100).round()}%',
            textAlign: TextAlign.right,
            style: AppText.secondary.copyWith(
              color: themeState.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
