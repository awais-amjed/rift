import 'package:flutter/widgets.dart';

/// Cuts at the right edge, and keeps [spill] to the left.
///
/// The members panel opens by widening from the right, its contents pinned
/// to their real width and sliding out through that edge, so the right is
/// the only side anything overflows. A plain `ClipRect` cut the left too, and
/// with it the floating panel's shadow: it ended in a hard line one gutter
/// from the panel instead of fading out. Top and bottom stay cut: the panel
/// runs the workspace's full height, the scrim stops at the same lines, and a
/// shadow past them fell on the undimmed title bar and gutter as a smudge.
class RightEdgeClipper extends CustomClipper<Rect> {
  /// How far past the left edge is kept: room for the shadow's blur.
  final double spill;

  const RightEdgeClipper({required this.spill});

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-spill, 0, size.width, size.height);

  @override
  bool shouldReclip(RightEdgeClipper old) => old.spill != spill;
}
