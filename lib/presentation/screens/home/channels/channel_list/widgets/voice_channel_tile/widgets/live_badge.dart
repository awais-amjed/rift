import 'package:flutter/material.dart';

import '../../../../../../../../data/constants.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/custom_colors.dart';

/// The pulsing LIVE tag on a voice channel you're connected to.
///
/// The pulse is a ring that expands and fades rather than a blinking dot: it
/// reads as "ongoing" in peripheral vision, which is the whole job, without
/// flashing hard enough to pull the eye off what you're reading.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: CustomColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Ring grows to 5px and fades out over the first 70% of the
              // cycle, then rests — matching the design's keyframes.
              final t = (_controller.value / 0.7).clamp(0.0, 1.0);
              return Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: CustomColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CustomColors.success.withValues(
                        alpha: 0.45 * (1 - t),
                      ),
                      spreadRadius: 5 * t,
                    ),
                  ],
                ),
              );
            },
          ),
          Text(
            'LIVE',
            style: AppText.sectionLabel.copyWith(
              letterSpacing: 0.6,
              color: CustomColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
