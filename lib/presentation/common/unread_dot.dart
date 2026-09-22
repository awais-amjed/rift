import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Small accent dot — a presence-only unread hint (e.g. "another server has
/// activity") where a number would be noise.
class UnreadDot extends StatelessWidget {
  final double size;

  const UnreadDot({super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: themeState.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}
