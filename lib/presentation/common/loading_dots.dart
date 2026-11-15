import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Three dots that pulse in sequence — the app's one way of saying "working".
///
/// Everywhere something waits, from the typing indicator to a roster still
/// loading. Not Material's spinner: that arrives in its own blue, at its own
/// size, and reads as a different app for as long as it turns.
///
/// The pulse steps about fifteen times a second rather than running as an
/// animation, for the reason `SpeakingRing` steps its fade: an animation
/// draws a frame on every vsync, 165 a second on a 165 Hz laptop, and dots
/// that wait for a roster or a picture can be on screen for minutes. A
/// fade this gentle looks the same at fifteen.
class LoadingDots extends StatefulWidget {
  final Color color;

  /// Diameter of one dot. The typing row uses the default; a body waiting on
  /// a page has room for more.
  final double dotSize;

  const LoadingDots({super.key, required this.color, this.dotSize = 4});

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots> {
  /// The steps in one pass of the three dots; each one is a frame.
  static const int _steps = 16;

  /// One pass of the three dots is 1100 ms. A loop, so it has no
  /// `AppMotion` length.
  static const Duration _stepEvery = Duration(microseconds: 1100000 ~/ _steps);

  /// Where in the pass the dots are, from 0 to [_steps] - 1.
  final ValueNotifier<int> _step = ValueNotifier(0);

  Timer? _timer;

  /// Stopped where animations are, as a [Timer] is not stopped by
  /// [TickerMode] by itself: a page kept offstage under another, or the
  /// whole app while nobody can see it (`AppSeenListener`).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(
        _stepEvery,
        (_) => _step.value = (_step.value + 1) % _steps,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = widget.dotSize;
    final gap = dot * 0.75;
    // Its own layer, so a step repaints three dots and not the page round
    // them; and painted, so a step is a repaint and never a rebuild. The
    // Connecting screen took 13 ms a frame to draw on a phone, over the 8 a
    // 120 Hz screen has, when each dot sat in an Opacity.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(dot * 3 + gap * 2, dot),
        painter: _DotsPainter(
          step: _step,
          steps: _steps,
          color: widget.color,
          dotSize: dot,
          gap: gap,
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final ValueListenable<int> step;
  final int steps;
  final Color color;
  final double dotSize;
  final double gap;

  _DotsPainter({
    required this.step,
    required this.steps,
    required this.color,
    required this.dotSize,
    required this.gap,
  }) : super(repaint: step);

  @override
  void paint(Canvas canvas, Size size) {
    final value = step.value / steps;
    final radius = dotSize / 2;
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      // Each dot lags the previous by a fifth of the cycle.
      final phase = (value - i * 0.2) % 1.0;
      // Up then back down over the phase, for a gentle pulse.
      final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
      paint.color = color.withValues(alpha: color.a * (0.3 + 0.7 * t));
      canvas.drawCircle(
        Offset(radius + i * (dotSize + gap), radius),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.step != step ||
      old.color != color ||
      old.dotSize != dotSize ||
      old.gap != gap;
}
