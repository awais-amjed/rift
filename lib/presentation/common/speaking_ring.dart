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

  const SpeakingRing({
    super.key,
    required this.isSpeaking,
    required this.borderRadius,
    required this.child,
    this.bloom = 1,
  });

  @override
  State<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<SpeakingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
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
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: active
                ? AppShadows.speakingRing(
                    themeState.primary,
                    t: _controller.value,
                    bloom: widget.bloom,
                  )
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
