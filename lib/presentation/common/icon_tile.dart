import 'package:flutter/material.dart';

import '../../data/constants.dart';

/// A rounded, tinted square holding one icon.
///
/// The design opens most things with one of these — a dialog's header badge, a
/// file card's type glyph, an onboarding step's hero mark. They differ only in
/// scale, so the recipe (a 10% wash of the icon's own colour behind it) lives
/// here rather than being re-derived at each size.
class IconTile extends StatelessWidget {
  final IconData icon;

  /// Tints both the glyph and, at 10%, the square behind it.
  final Color color;

  final double size;
  final double radius;
  final double iconSize;

  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.size,
    required this.radius,
    required this.iconSize,
  });

  /// A dialog's header badge, the one scale every dialog title shares.
  const IconTile.title({super.key, required this.icon, required this.color})
    : size = 36,
      radius = K.radiusRow,
      iconSize = 18;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
