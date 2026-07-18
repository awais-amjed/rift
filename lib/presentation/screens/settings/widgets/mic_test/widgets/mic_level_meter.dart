import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// A segmented input-level bar. [level] is 0..1; segments light up from the
/// left, shifting green → amber → red toward the top of the range. When
/// [active] is false every segment is dimmed (test not running).
///
/// If [threshold] > 0, a marker line is drawn at that position (the
/// voice-activity gate point) and — while the current level is below it —
/// the lit segments are greyed to signal "not transmitting".
class MicLevelMeter extends StatelessWidget {
  final double level;
  final bool active;
  final double threshold;
  final ThemeState themeState;

  const MicLevelMeter({
    super.key,
    required this.level,
    required this.active,
    required this.themeState,
    this.threshold = 0.0,
  });

  static const _segments = 24;
  static const _height = 14.0;
  static const _green = Color(0xFF3BA55D);
  static const _amber = Color(0xFFFAA61A);

  Color _colorFor(int index) {
    final t = index / (_segments - 1);
    if (t < 0.6) return _green;
    if (t < 0.85) return _amber;
    return CustomColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final filled = (level.clamp(0.0, 1.0) * _segments).round();
    final gated = threshold > 0;
    final transmitting = !gated || level >= threshold;

    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Row(
              children: List.generate(_segments, (i) {
                final on = active && i < filled;
                final Color color;
                if (!on) {
                  color = themeState.bgActive.withValues(alpha: 0.6);
                } else if (!transmitting) {
                  // Below the gate threshold — lit but muted-looking.
                  color = themeState.textQuaternary;
                } else {
                  color = _colorFor(i);
                }
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (gated)
            Align(
              alignment: Alignment(threshold.clamp(0.0, 1.0) * 2 - 1, 0),
              child: Container(
                width: 2,
                height: _height,
                decoration: BoxDecoration(
                  color: themeState.textPrimary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
