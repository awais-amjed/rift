import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';

/// The noise-gate threshold control: how loud the mic must be before Rift
/// transmits at all.
///
/// The slider position *is* the threshold. That used to need a curve and a
/// squeezed range, because the level it compared against was the audio
/// visualizer's band peak, where a quiet room and a raised voice were only a
/// fifth of the scale apart and the top three quarters of the slider meant
/// "mute me". Levels are measured in decibels now, so the plain 0–1 travel
/// already lands evenly across the range a microphone actually produces and
/// the marker on the meter above sits exactly where this says it does.
class InputSensitivitySlider extends StatelessWidget {
  /// The stored gate threshold, on the same 0–1 scale as the level meter.
  final double threshold;

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
            value: threshold.clamp(0.0, 1.0),
            onChanged: onChanged,
            activeColor: themeState.primary,
            inactiveColor: themeState.bgActive,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            threshold <= 0 ? 'Off' : '${(threshold * 100).round()}%',
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
