import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';

/// Three bars that rise and fall while something is playing.
///
/// Decoration with a job: a shared track has no picture, so this is the only
/// thing on the tile that says the difference between music playing and a
/// share that has gone silent. It stands still rather than stopping when
/// [playing] is false, so the tile keeps its shape either way.
///
/// The bars step about fifteen times a second rather than running as an
/// animation, as `LoadingDots` do: an animation draws a frame on every
/// vsync, and a sound share plays for as long as the call lasts.
class SoundWaveIndicator extends StatefulWidget {
  final bool playing;
  final Color color;
  final double height;

  const SoundWaveIndicator({
    super.key,
    required this.playing,
    required this.color,
    this.height = 28,
  });

  @override
  State<SoundWaveIndicator> createState() => _SoundWaveIndicatorState();
}

class _SoundWaveIndicatorState extends State<SoundWaveIndicator> {
  /// The steps in one rise and fall of the bars; each one is a frame.
  static const int _steps = 14;

  /// One rise and fall is 900 ms. A loop, so it has no `AppMotion` length.
  static const Duration _stepEvery = Duration(microseconds: 900000 ~/ _steps);

  /// Where in the rise and fall the bars are, from 0 to [_steps] - 1.
  final ValueNotifier<int> _step = ValueNotifier(0);

  Timer? _timer;

  /// Whether animations may run here ([TickerMode]), which a [Timer] does
  /// not hear by itself: off while nobody can see Rift (`AppSeenListener`).
  bool _tickersOn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersOn = TickerMode.valuesOf(context).enabled;
    _run();
  }

  @override
  void didUpdateWidget(SoundWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) _run();
  }

  void _run() {
    if (widget.playing && _tickersOn) {
      _timer ??= Timer.periodic(
        _stepEvery,
        (_) => _step.value = (_step.value + 1) % _steps,
      );
    } else {
      _timer?.cancel();
      _timer = null;
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
    // Its own layer, so a step repaints three bars and not the tile.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(
          _BarsPainter.bars * _BarsPainter.barWidth +
              (_BarsPainter.bars - 1) * _BarsPainter.spacing,
          widget.height,
        ),
        painter: _BarsPainter(
          step: _step,
          steps: _steps,
          playing: widget.playing,
          color: widget.color,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  static const int bars = 3;
  static const double barWidth = 4;
  static const double spacing = 4;

  final ValueListenable<int> step;
  final int steps;
  final bool playing;
  final Color color;

  _BarsPainter({
    required this.step,
    required this.steps,
    required this.playing,
    required this.color,
  }) : super(repaint: step);

  /// A bar's height as a fraction of the full one, offset per bar so they
  /// don't move as a block. Silent, all three rest low.
  double _fraction(int index) {
    if (!playing) return 0.35;
    final phase =
        step.value / steps * 2 * math.pi + index * (2 * math.pi / bars);
    return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final height = size.height * _fraction(i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * (barWidth + spacing),
            (size.height - height) / 2,
            barWidth,
            height,
          ),
          const Radius.circular(K.radiusPill),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.step != step || old.playing != playing || old.color != color;
}
