import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where a stream card goes: beside its row, centred on it, or under it on a
/// phone — then pushed back inside the window, since a card centred on a row
/// near the top or the foot of the sidebar would hang off the edge.
class StreamCardLayout extends SingleChildLayoutDelegate {
  /// The row, in the overlay's coordinates.
  final Rect anchor;
  final bool below;

  /// Between the row and the card, and between the card and the window.
  static const double gap = 12;
  static const double margin = 12;

  const StreamCardLayout({required this.anchor, required this.below});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        constraints.biggest,
      ).deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double clamp(double value, double room) =>
        value.clamp(margin, math.max(margin, room - margin)).toDouble();
    if (below) {
      return Offset(
        clamp(
          anchor.center.dx - childSize.width / 2,
          size.width - childSize.width,
        ),
        clamp(anchor.bottom + gap / 2, size.height - childSize.height),
      );
    }
    return Offset(
      clamp(anchor.right + gap, size.width - childSize.width),
      clamp(
        anchor.center.dy - childSize.height / 2,
        size.height - childSize.height,
      ),
    );
  }

  @override
  bool shouldRelayout(StreamCardLayout old) =>
      old.anchor != anchor || old.below != below;
}
