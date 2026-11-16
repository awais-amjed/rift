import 'dart:ui';

import '../../data/enums/stream_pip_corner.dart';

/// The width a floating picture resting in [corner], [from] wide, takes when
/// its grip moves [moved] in one step of a pull.
///
/// It grows away from its corner, which stays put: by whichever way the
/// pointer moved further in this step, across or down at its own [aspect].
/// Called once a step, from the width the last step left — never from the
/// width the last frame drew, since a mouse reports several steps a frame.
/// Judged over a whole pull instead, it jumped wherever the pull went out
/// one way and in the other, from following one to following the other.
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
