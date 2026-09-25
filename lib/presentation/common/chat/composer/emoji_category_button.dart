import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';

/// One category's icon along the emoji picker's edge; pressing it scrolls the
/// grid to that category.
class EmojiCategoryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const EmojiCategoryButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(K.radiusRow),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: K.iconRow, color: themeState.textQuaternary),
      ),
    );
  }
}
