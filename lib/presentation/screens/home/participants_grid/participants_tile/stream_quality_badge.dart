import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/video_stream_stats.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// "1080p · 60fps" beside a sharer's name, in the name badge's glass: what
/// the sharer says they send, or else what arrives. Draws nothing until one
/// of them is known.
///
/// The sharer's word wins because a measured rate is not the share's rate: a
/// screen that stands still sends fewer frames, so a 60fps share read 30 one
/// second and 60 the next. The exact numbers are in the stats overlay.
class StreamQualityBadge extends StatelessWidget {
  final VideoStreamStats? stats;
  final String? sent;

  const StreamQualityBadge({super.key, required this.stats, this.sent});

  @override
  Widget build(BuildContext context) {
    final label = sent ?? stats?.qualityLabel;
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
