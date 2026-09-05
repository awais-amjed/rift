import 'package:flutter/material.dart';

/// Three dots that pulse in sequence — the app's one way of saying "working".
///
/// Everywhere something waits, from the typing indicator to a roster still
/// loading. Not Material's spinner: that arrives in its own blue, at its own
/// size, and reads as a different app for as long as it turns.
class LoadingDots extends StatefulWidget {
  final Color color;

  /// Diameter of one dot. The typing row uses the default; a body waiting on
  /// a page has room for more.
  final double dotSize;

  const LoadingDots({super.key, required this.color, this.dotSize = 4});

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.dotSize * 0.75;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot lags the previous by a fifth of the cycle.
            final phase = (_controller.value - i * 0.2) % 1.0;
            // Ease up then back down over the phase for a gentle pulse.
            final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? gap : 0),
              child: Opacity(
                opacity: 0.3 + 0.7 * t,
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
