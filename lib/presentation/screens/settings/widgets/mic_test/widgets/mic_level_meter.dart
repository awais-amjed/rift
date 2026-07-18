import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// A segmented input-level bar. [level] is 0..1; segments light up from the
/// left, shifting green → amber → red toward the top of the range. When
/// [active] is false every segment is dimmed (test not running).
class MicLevelMeter extends StatelessWidget {
  final double level;
  final bool active;
  final ThemeState themeState;

  const MicLevelMeter({
    super.key,
    required this.level,
    required this.active,
    required this.themeState,
  });

  static const _segments = 24;
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
    return Row(
      children: List.generate(_segments, (i) {
        final on = active && i < filled;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            height: 10,
            decoration: BoxDecoration(
              color: on
                  ? _colorFor(i)
                  : themeState.bgActive.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
