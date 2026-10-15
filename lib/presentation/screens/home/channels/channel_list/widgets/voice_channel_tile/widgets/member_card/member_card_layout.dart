import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Which side of its row a member card opens on.
enum MemberCardSide {
  /// Out over the page from the channel list.
  right,

  /// Out over the page from the members sidebar, on the window's right.
  left,

  /// Under the row on a phone, where there is no room beside it.
  below,
}

/// Where a member card goes: beside its row and centred on it, or under it —
/// then pushed back inside the window, since a card centred on a row near the
/// top or the foot of a sidebar would hang off the edge.
class MemberCardLayout extends SingleChildLayoutDelegate {
  /// The row, in the overlay's coordinates.
  final Rect anchor;
  final MemberCardSide side;

  /// Between the row and the card, and between the card and the window.
  static const double gap = 12;
  static const double margin = 12;

  const MemberCardLayout({required this.anchor, required this.side});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        constraints.biggest,
      ).deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double clamp(double value, double room) =>
        value.clamp(margin, math.max(margin, room - margin)).toDouble();
    if (side == MemberCardSide.below) {
      return Offset(
        clamp(
          anchor.center.dx - childSize.width / 2,
          size.width - childSize.width,
        ),
        clamp(anchor.bottom + gap / 2, size.height - childSize.height),
      );
    }
    return Offset(
      clamp(
        side == MemberCardSide.right
            ? anchor.right + gap
            : anchor.left - gap - childSize.width,
        size.width - childSize.width,
      ),
      clamp(
        anchor.center.dy - childSize.height / 2,
        size.height - childSize.height,
      ),
    );
  }

  @override
  bool shouldRelayout(MemberCardLayout old) =>
      old.anchor != anchor || old.side != side;
}
