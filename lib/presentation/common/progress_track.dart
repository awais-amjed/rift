import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_motion.dart';
import '../theme/theme_context.dart';

/// A thin bar filling with the accent as something moves along: a file
/// uploading under its message, an update downloading in Settings. Each step
/// slides rather than jumps.
class ProgressTrack extends StatelessWidget {
  static const double _height = 4;

  /// 0 to 1.
  final double progress;

  const ProgressTrack({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusPill),
      child: Container(
        height: _height,
        color: theme.bgTertiary,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress.clamp(0.0, 1.0)),
          duration: AppMotion.state,
          curve: AppMotion.settle,
          builder: (context, value, _) => FractionallySizedBox(
            widthFactor: value,
            child: Container(color: theme.primary),
          ),
        ),
      ),
    );
  }
}
