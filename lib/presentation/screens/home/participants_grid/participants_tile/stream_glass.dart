import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/theme_context.dart';

/// The frosted fill the controls in a watched stream's corner sit on — the
/// same glass as the badges in the opposite corner, so the two read as one
/// set.
class StreamGlass extends StatelessWidget {
  final Widget child;

  const StreamGlass({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.bgSecondary.withValues(alpha: 0.85),
            borderRadius: radius,
            border: Border.all(color: theme.borderElevated),
          ),
          // Inside the fill, or the hover is painted under it.
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}
