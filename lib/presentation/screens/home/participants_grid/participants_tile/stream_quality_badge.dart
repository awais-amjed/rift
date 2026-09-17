import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/video_stats_sampler.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// "1080p · 60fps" beside a sharer's name, in the name badge's glass. Draws
/// nothing until the picture size is known.
class StreamQualityBadge extends StatelessWidget {
  final VideoStreamStats? stats;

  const StreamQualityBadge({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final label = stats?.qualityLabel;
    if (label == null) return const SizedBox.shrink();
    final theme = context.theme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: theme.bgSecondary.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: theme.borderElevated),
          ),
          child: Text(
            label,
            style: AppText.chip.copyWith(color: theme.textSecondary),
          ),
        ),
      ),
    );
  }
}
