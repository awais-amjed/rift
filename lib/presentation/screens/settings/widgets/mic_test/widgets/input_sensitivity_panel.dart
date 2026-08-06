import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';
import 'input_sensitivity_slider.dart';
import 'mic_level_meter.dart';

/// The level meter and the threshold that is read against it, with the wording
/// that explains how the two relate.
///
/// Bar, marker and slider are all the same 0–1 measurement, so a voice that
/// reaches the marker is a voice that opens the gate. Keeping them in one
/// widget is what makes that easy to keep true.
class InputSensitivityPanel extends StatelessWidget {
  /// The current microphone level, 0–1 on `PcmLevel`'s scale.
  final double level;

  /// Whether a mic test is running, which is what makes the meter live.
  final bool testing;

  /// The gate threshold, on the same scale as [level].
  final double threshold;

  final ValueChanged<double> onThresholdChanged;

  /// Push-to-talk overrides the gate, so the threshold is noted as ignored
  /// rather than silently doing nothing.
  final bool pushToTalkEnabled;

  final ThemeState themeState;

  const InputSensitivityPanel({
    super.key,
    required this.level,
    required this.testing,
    required this.threshold,
    required this.onThresholdChanged,
    required this.pushToTalkEnabled,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Input Sensitivity',
          style: AppText.row.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'How loud your mic must be to transmit. Drag the threshold, then '
          'Test Mic and speak — input left of the marker is muted. Leave at '
          '0% for an open mic.',
          style: AppText.secondary.copyWith(
            color: themeState.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        MicLevelMeter(
          level: level,
          active: testing,
          threshold: threshold,
          themeState: themeState,
        ),
        const SizedBox(height: 10),
        InputSensitivitySlider(
          threshold: threshold,
          onChanged: onThresholdChanged,
          themeState: themeState,
        ),
        if (pushToTalkEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Ignored while Push-to-Talk is on.',
              style: AppText.label.copyWith(
                color: themeState.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}
