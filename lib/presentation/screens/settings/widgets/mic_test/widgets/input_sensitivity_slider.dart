import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/services/mic_level_scale.dart';
import '../../../../../theme/app_text.dart';

/// The noise-gate threshold control: how loud the mic must be before Rift
/// transmits at all.
///
/// Drawn on [MicLevelScale] rather than on the raw level the gate compares
/// against — see that class for why a straight 0–1 slider was mostly a mute
/// switch.
///
/// The travel is curved, but the percentage shown is the marker's position on
/// the meter above, so the number and the line agree. Labelling the travel
/// instead would put "50%" next to a marker a quarter of the way along.
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
            threshold <= 0
                ? 'Off'
                : '${(MicLevelScale.toMeter(threshold) * 100).round()}%',
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
