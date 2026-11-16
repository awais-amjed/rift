import 'dart:ui';

import '../../data/enums/stream_pip_corner.dart';

/// The width a floating picture resting in [corner] takes when its grip has
/// been pulled [moved] since the pull began at [from] wide.
///
/// From the pull as a whole, never step by step: a mouse reports a pull as
/// a run of one-pixel steps, and judged one at a time, a pixel's drift back
/// against the pull shrank the picture in the middle of growing it. Of the
/// two ways it could change — across, or down at its own [aspect] — it
/// follows the one the grip has gone further in, either way.
double pipResizedWidth({
  required double from,
  required Offset moved,
  required StreamPipCorner corner,
  required double aspect,
}) {
  final across = corner.isLeft ? moved.dx : -moved.dx;
  final down = (corner.isTop ? moved.dy : -moved.dy) * aspect;
  return from + (across.abs() >= down.abs() ? across : down);
}
