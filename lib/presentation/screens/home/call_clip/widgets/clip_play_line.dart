import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../theme/theme_context.dart';

/// A line over the waveform where Play plays from, and where the preview has
/// reached while it plays: [head], a fraction of the clip (`ClipPreview`).
///
/// Painted alone in a [RepaintBoundary] from [head], which the preview steps
/// on a timer: each step repaints the line and nothing else, the bars under
/// it included.
class ClipPlayLine extends StatelessWidget {
  final ValueListenable<double> head;

  const ClipPlayLine({super.key, required this.head});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _PlayLinePainter(
            head: head,
            color: context.theme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PlayLinePainter extends CustomPainter {
  final ValueListenable<double> head;
  final Color color;

  _PlayLinePainter({required this.head, required this.color})
    : super(repaint: head);

  @override
  void paint(Canvas canvas, Size size) {
    final x = head.value.clamp(0.0, 1.0) * size.width;
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
      old.head != head || old.color != color;
}
