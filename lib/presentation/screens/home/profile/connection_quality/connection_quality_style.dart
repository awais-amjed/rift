import 'package:flutter/material.dart';

import '../../../../../data/enums/voice_quality.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// How a [VoiceQuality] is drawn: icon, colour, and wording.
///
/// The indicator and its popup are one badge shown at two sizes, so they have
/// to agree — a grade that reads Fair on the bar and Good in the panel is a
/// bug the user sees before we do. They each carried their own copy of these
/// three switches, and adding `excellent` meant editing all six.
class ConnectionQualityStyle {
  const ConnectionQualityStyle._();

  /// Signal bars, thinning out as the grade drops.
  static IconData icon(VoiceQuality quality) => switch (quality) {
    VoiceQuality.excellent => Icons.signal_cellular_4_bar,
    VoiceQuality.good => Icons.signal_cellular_alt,
    VoiceQuality.fair => Icons.signal_cellular_alt_2_bar,
    VoiceQuality.poor => Icons.signal_cellular_0_bar,
    VoiceQuality.unknown => Icons.signal_cellular_null,
  };

  /// Semantic colours rather than literal greens and ambers, so the badge
  /// reads against whichever palette is running instead of fighting it.
  static Color color(VoiceQuality quality, ThemeState themeState) =>
      switch (quality) {
        VoiceQuality.excellent || VoiceQuality.good => CustomColors.success,
        VoiceQuality.fair => CustomColors.warning,
        VoiceQuality.poor => CustomColors.error,
        VoiceQuality.unknown => themeState.textQuaternary,
      };

  /// [unknown] is the caller's to choose: with no reading yet the compact
  /// badge says there is no data, while the panel, which is only open because
  /// somebody is looking at it, says the call is still connecting.
  static String label(VoiceQuality quality, {required String unknown}) =>
      switch (quality) {
        VoiceQuality.excellent => 'Excellent',
        VoiceQuality.good => 'Good',
        VoiceQuality.fair => 'Fair',
        VoiceQuality.poor => 'Poor',
        VoiceQuality.unknown => unknown,
      };
}
