import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// The grip at the top of a bottom sheet, which is what says it can be
/// dragged away.
class SheetHandle extends StatelessWidget {
  /// Space around the grip. Each sheet sits it against different content,
  /// so the gap is the caller's.
  final EdgeInsetsGeometry margin;

  const SheetHandle({
    super.key,
    this.margin = const EdgeInsets.only(top: 8, bottom: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: margin,
        decoration: BoxDecoration(
          color: context.theme.borderElevated,
          borderRadius: BorderRadius.circular(K.radiusPill),
        ),
      ),
    );
  }
}
