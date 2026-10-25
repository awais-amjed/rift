import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/theme_context.dart';

/// Wraps anything that should glow while its owner is talking — a voice tile,
/// an avatar in the sidebar roster.
///
/// The ring fades in when its owner starts talking and out when they stop,
/// and holds still in between. It used to breathe for as long as anyone
/// talked, and every breath was a frame: the whole window redrawn sixty
/// times a second, minimised or covered too, which on a laptop cost a game
/// beside the call more than a noise model did (Oct 25). Speech already
/// switches the ring on and off with every pause, so it still reads as
/// something happening now.
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
  /// How far the ring has faded in: 0 gone, 1 shown.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.state,
    value: widget.isSpeaking ? 1 : 0,
  );

  @override
  void didUpdateWidget(SpeakingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking == oldWidget.isSpeaking) return;
    if (widget.isSpeaking) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The fade is the painter's own: it repaints on every tick of the
    // controller without a rebuild. And both boundaries matter. Without the
    // outer one each frame of a fade repainted whatever shared the ring's
    // layer — the whole sidebar, the whole stage; without the inner one the
    // child, a video or an avatar, is repainted under the ring every frame.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _RingPainter(
          fade: _controller,
          accent: context.theme.primary,
          bloom: widget.bloom,
          borderRadius: widget.borderRadius,
          gap: widget.gap,
        ),
        child: RepaintBoundary(child: widget.child),
      ),
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
  final Animation<double> fade;
  final Color accent;
  final double bloom;
  final BorderRadius borderRadius;
  final double gap;

  _RingPainter({
    required this.fade,
    required this.accent,
    required this.bloom,
    required this.borderRadius,
    required this.gap,
  }) : super(repaint: fade);

  @override
  void paint(Canvas canvas, Size size) {
    final shown = fade.value;
    if (shown == 0) return;
    final box = borderRadius.toRRect(Offset.zero & size);
    for (final shadow in AppShadows.speakingRing(accent, bloom: bloom)) {
      final inner = box.shift(shadow.offset).inflate(gap);
      final outer = inner.inflate(shadow.spreadRadius);
      final paint = shadow
          .copyWith(
            color: shadow.color.withValues(alpha: shadow.color.a * shown),
          )
          .toPaint();
      if (gap > 0) {
        canvas.drawDRRect(outer, inner, paint);
      } else {
        canvas.drawRRect(outer, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fade != fade ||
      old.accent != accent ||
      old.bloom != bloom ||
      old.borderRadius != borderRadius ||
      old.gap != gap;
}
