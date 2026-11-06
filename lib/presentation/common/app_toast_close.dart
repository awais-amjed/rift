import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// The small close on a toast or a message banner.
class AppToastClose extends StatelessWidget {
  final VoidCallback onTap;

  const AppToastClose({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close_rounded,
            size: K.iconRow,
            color: theme.textTertiary,
          ),
        ),
      ),
    );
  }
}
