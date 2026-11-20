import 'package:material_ui/material_ui.dart';

import '../../../../theme/theme_context.dart';

/// The clip as bars, one a peak ([ClipTrim.peaks]), the selection between
/// [start] and [end] (fractions of the clip) in the accent and the rest
/// dimmed. Drawn alone in a [RepaintBoundary]: a drag of a handle repaints
/// the bars and nothing round them.
class ClipWaveform extends StatelessWidget {
  final List<double> peaks;
  final double start;
  final double end;

  const ClipWaveform({
    super.key,
    required this.peaks,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(
          peaks: peaks,
          start: start,
          end: end,
          selected: theme.accentBright,
          rest: theme.textQuaternary,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double start;
  final double end;
  final Color selected;
  final Color rest;

  _WaveformPainter({
    required this.peaks,
    required this.start,
    required this.end,
    required this.selected,
    required this.rest,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final step = size.width / peaks.length;
    final bar = (step * 0.6).clamp(1.0, 4.0);
    final mid = size.height / 2;
    final on = Paint()..color = selected;
    final off = Paint()..color = rest;
    for (var i = 0; i < peaks.length; i++) {
      final at = (i + 0.5) / peaks.length;
      // Never thinner than a line, so silence still reads as the clip.
      final half = (peaks[i] * mid).clamp(0.75, mid);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset((i + 0.5) * step, mid),
            width: bar,
            height: half * 2,
          ),
          Radius.circular(bar / 2),
        ),
        at >= start && at <= end ? on : off,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks ||
      old.start != start ||
      old.end != end ||
      old.selected != selected ||
      old.rest != rest;
}
