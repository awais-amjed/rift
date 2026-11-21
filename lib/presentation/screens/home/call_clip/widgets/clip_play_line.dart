import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../logic/services/call_clip/clip_trim.dart';
import '../../../../theme/theme_context.dart';

/// A line over the waveform at the point the preview has reached, while it
/// plays ([played] is null otherwise). [start] and [end] are the selection,
/// as fractions of the clip, and [length] how long it plays.
///
/// Painted alone in a [RepaintBoundary] from [played], which
/// `ClipPreviewButton` steps on a timer: each step repaints the line and
/// nothing else, the bars under it included.
class ClipPlayLine extends StatelessWidget {
  final ValueListenable<Duration?> played;
  final double start;
  final double end;
  final Duration length;

  const ClipPlayLine({
    super.key,
    required this.played,
    required this.start,
    required this.end,
    required this.length,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _PlayLinePainter(
            played: played,
            start: start,
            end: end,
            length: length,
            color: context.theme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PlayLinePainter extends CustomPainter {
  final ValueListenable<Duration?> played;
  final double start;
  final double end;
  final Duration length;
  final Color color;

  _PlayLinePainter({
    required this.played,
    required this.start,
    required this.end,
    required this.length,
    required this.color,
  }) : super(repaint: played);

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = played.value;
    if (elapsed == null) return;
    final x =
        ClipTrim.playhead(
          start: start,
          end: end,
          elapsed: elapsed,
          length: length,
        ) *
        size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PlayLinePainter old) =>
      old.played != played ||
      old.start != start ||
      old.end != end ||
      old.length != length ||
      old.color != color;
}
