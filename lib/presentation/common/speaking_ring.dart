import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/theme_context.dart';

/// Wraps anything that should glow while its owner is talking — a voice tile,
/// an avatar in the sidebar roster.
///
/// The ring breathes rather than sitting still. A static ring reads as a
/// property of the tile ("this one is highlighted"); a moving one reads as
/// something happening right now, which is what speech is.
class SpeakingRing extends StatefulWidget {
  final bool isSpeaking;
  final BorderRadius borderRadius;
  final Widget child;

  /// Scales the halo for large surfaces. A voice tile's glow has to carry
  /// across a 16:9 card; an avatar's must not swamp the row it sits in.
  final double bloom;

  /// Clear space between the child and the ring, as the rail's selected chip
  /// has. Left see-through rather than filled, so it shows whatever the row
  /// behind is tinted — a hover, the call's own card.
  final double gap;

  const SpeakingRing({
    super.key,
    required this.isSpeaking,
    required this.borderRadius,
    required this.child,
    this.bloom = 1,
    this.gap = 0,
  });

  @override
  State<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<SpeakingRing>
    with SingleTickerProviderStateMixin {
  /// One breath of the ring. A loop, so it has no `AppMotion` length.
  static const _cycle = Duration(milliseconds: 1300);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSpeaking) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SpeakingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking == oldWidget.isSpeaking) return;
    if (widget.isSpeaking) {
      _controller.repeat(reverse: true);
    } else {
      // Stop at rest rather than wherever the pulse happened to be, so the
      // ring doesn't freeze mid-bloom when someone stops talking.
      _controller.animateTo(0, duration: AppMotion.state);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final active = widget.isSpeaking || _controller.value > 0;
        return CustomPaint(
          painter: _RingPainter(
            borderRadius: widget.borderRadius,
            gap: widget.gap,
            shadows: active
                ? AppShadows.speakingRing(
                    themeState.primary,
                    t: _controller.value,
                    bloom: widget.bloom,
                  )
                : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Paints the ring's shadows with corners that grow with their spread.
///
/// A [BoxDecoration] shadow keeps the box's own radius on the bigger,
/// spread-out rectangle, so the ring came out squarer than what it surrounds.
/// Round a 24px avatar that was plain to see: each time somebody started or
/// stopped talking, their picture looked to switch from a squircle to a
/// square and back.
///
/// With a [gap], each shadow is drawn as a band starting that far out, so the
/// space next to the child stays empty.
class _RingPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final double gap;
  final List<BoxShadow> shadows;

  const _RingPainter({
    required this.borderRadius,
    required this.gap,
    required this.shadows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final box = borderRadius.toRRect(Offset.zero & size);
    for (final shadow in shadows) {
      final inner = box.shift(shadow.offset).inflate(gap);
      final outer = inner.inflate(shadow.spreadRadius);
      if (gap > 0) {
        canvas.drawDRRect(outer, inner, shadow.toPaint());
      } else {
        canvas.drawRRect(outer, shadow.toPaint());
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.borderRadius != borderRadius ||
      old.gap != gap ||
      !listEquals(old.shadows, shadows);
}
