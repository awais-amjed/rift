import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import 'rift_mark_path.dart';

/// Rift's brand mark, in the palette's identity gradient.
///
/// The mark is two walls with the rift as the gap between them — see
/// [riftMarkPath]. It is a shape, not a tile: no container, no glow, and the
/// gap is whatever ground it sits on, so it holds on the canvas, on a panel
/// and beside a server chip without being one. It themes with the app the
/// way it always has, through the identity gradient; outside the app —
/// installers, favicons — it is pinned to Indigo (`assets/brand/`).
///
/// Keep 0.2× the mark's width clear around it. Do not go below
/// [riftMarkMinimumSize].
class AppMark extends StatelessWidget {
  final double size;

  const AppMark({super.key, this.size = 16})
    : assert(size >= riftMarkMinimumSize, 'the mark closes up below 16px');

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(gradient: context.theme.identityGradient),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final LinearGradient gradient;

  const _MarkPainter({required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..isAntiAlias = true;
    canvas.drawPath(riftMarkPath(size.width), paint);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.gradient != gradient;
}
