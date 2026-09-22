import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../../data/constants.dart';

/// Three bars that rise and fall while something is playing.
///
/// Decoration with a job: a shared track has no picture, so this is the only
/// thing on the tile that says the difference between music playing and a
/// share that has gone silent. It stands still rather than stopping when
/// [playing] is false, so the tile keeps its shape either way.
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

class _SoundWaveIndicatorState extends State<SoundWaveIndicator>
    with SingleTickerProviderStateMixin {
  static const _bars = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(SoundWaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      // Stopped where it stands, then eased back to the resting height by the
      // AnimatedContainer below.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A bar's height as a fraction of the full one, offset per bar so they
  /// don't move as a block.
  double _fraction(int index, double t) {
    if (!widget.playing) return 0.35;
    final phase = t * 2 * math.pi + index * (2 * math.pi / _bars);
    return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 4,
          children: [
            for (var i = 0; i < _bars; i++)
              Container(
                width: 4,
                height: widget.height * _fraction(i, _controller.value),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(K.radiusPill),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
