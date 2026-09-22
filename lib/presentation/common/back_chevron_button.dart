import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// The way back on a phone: a page header, a full-screen dialog, a sheet's
/// submenu, settings, onboarding.
///
/// One widget so the glyph and its size are decided once. The six copies it
/// replaced had already drifted to two sizes.
class BackChevronButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  /// A chevron is mostly empty space, so it is drawn larger than the arrow
  /// it replaced to read at the same weight.
  static const double _iconSize = 28;

  const BackChevronButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Back',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: K.touchTargetMin,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          Icons.chevron_left_rounded,
          size: _iconSize,
          color: context.theme.textSecondary,
        ),
      ),
    );
  }
}
