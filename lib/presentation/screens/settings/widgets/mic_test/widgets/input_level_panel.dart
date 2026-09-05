import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
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
          style: AppText.row.copyWith(color: themeState.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          // "selected above" only means something where there is a picker
          // above to have selected in. On a phone there is not — the OS owns
          // routing there — so the sentence would be pointing at nothing.
          HostPlatform.isMobile
              ? 'Test Mic and speak — the bar should move with your voice. If '
                    'it stays dark, Rift is not hearing your microphone.'
              : 'Test Mic and speak — the bar should move with your voice. If '
                    'it stays dark, Rift is not hearing the input device '
                    'selected above.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 12),
        MicLevelMeter(level: level, active: testing, themeState: themeState),
      ],
    );
  }
}
