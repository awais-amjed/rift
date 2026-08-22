import 'package:flutter/material.dart';

import '../../../../../../data/classes/ping_sample.dart';

/// A small line graph that renders [PingSample] history.
/// X-axis = last 5 minutes, Y-axis = ping in ms.
class PingGraph extends StatelessWidget {
  final List<PingSample> samples;
  final double height;

  const PingGraph({super.key, required this.samples, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _PingGraphPainter(samples: samples)),
    );
  }
}

class _PingGraphPainter extends CustomPainter {
  final List<PingSample> samples;

  const _PingGraphPainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final now = DateTime.now();
    const windowMs = 5 * 60 * 1000.0; // 5 minutes in ms

    final maxRtt = samples.fold<double>(
      200.0,
      (prev, s) => s.rttMs > prev ? s.rttMs : prev,
    );

    // Horizontal guide lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    for (final lineMs in [50.0, 100.0, 150.0, 200.0]) {
      if (lineMs > maxRtt * 1.05) break;
      final y = size.height - (lineMs / maxRtt) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Build paths
    final fillPath = Path();
    final linePath = Path();
    bool first = true;

    for (final sample in samples) {
      final ageMs = now.difference(sample.time).inMilliseconds.toDouble();
      final x = size.width - (ageMs / windowMs) * size.width;
      final y = size.height - (sample.rttMs / maxRtt) * size.height;

      if (first) {
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        linePath.moveTo(x, y);
        first = false;
      } else {
        fillPath.lineTo(x, y);
        linePath.lineTo(x, y);
      }
    }

    // Carry the newest reading along to the right edge.
    //
    // Samples are only recorded when the measurement actually changes — ICE
    // refreshes the round trip every few seconds while the poll runs every
    // second, so appending every poll would invent resolution the data never
    // had. The cost is that the newest sample can be well to the left of now,
    // and on a connection steady enough to produce one reading for five
    // minutes there was a single point and, with the old two-sample minimum,
    // nothing drawn at all. The last reading still stands until another one
    // replaces it, so extending it is what the numbers actually say.
    final lastY = size.height - (samples.last.rttMs / maxRtt) * size.height;
    linePath.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.35),
          const Color(0xFF6366F1).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(_PingGraphPainter old) => old.samples != samples;
}
