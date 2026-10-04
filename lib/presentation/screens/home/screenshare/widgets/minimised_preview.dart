import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Stands in for the picture of a minimised window, which has none until it
/// is back on screen — and says when its share will start: once the user
/// opens it, which Rift leaves to them.
class MinimisedPreview extends StatelessWidget {
  const MinimisedPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.minimize_rounded, size: 22, color: theme.textTertiary),
            const SizedBox(height: 4),
            Text(
              'Minimised',
              style: AppText.label.copyWith(color: theme.textSecondary),
            ),
            Text(
              'Starts when you open it',
              textAlign: TextAlign.center,
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
