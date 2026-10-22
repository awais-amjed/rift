import 'package:flutter/widgets.dart';

/// Cuts at the right edge only.
///
/// The members panel opens by widening from the right, its contents pinned
/// to their real width and sliding out through that edge, so the right is
/// the only side anything overflows. A plain `ClipRect` cut the other three
/// too, and with them the floating panel's shadow: it ended in a hard line
/// one gutter from the panel instead of fading out over the scrim.
class RightEdgeClipper extends CustomClipper<Rect> {
  /// How far past the other three edges is kept: room for the shadow.
  final double spill;

  const RightEdgeClipper({required this.spill});

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-spill, -spill, size.width, size.height + spill);

  @override
  bool shouldReclip(RightEdgeClipper old) => old.spill != spill;
}
