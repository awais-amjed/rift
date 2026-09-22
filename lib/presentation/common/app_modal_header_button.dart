import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';
import 'app_modal_header.dart';

/// One icon button in a modal's header: the close, or an action beside it.
/// 32px square, the row radius, tertiary ink.
class AppModalHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const AppModalHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: themeState.textTertiary, size: 18),
      constraints: const BoxConstraints.tightFor(
        width: AppModalHeader.buttonSize,
        height: AppModalHeader.buttonSize,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
      ),
    );
  }
}
