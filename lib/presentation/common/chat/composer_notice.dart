import 'package:flutter/material.dart';

import '../../../data/constants.dart';
import '../../theme/app_text.dart';
import '../../theme/theme_context.dart';

/// A line in the composer's place, saying why there is no composer.
///
/// Taking the composer's slot rather than sitting above the list is the
/// point: the thing it explains is the thing that is missing. A locked
/// channel, a request waiting to be accepted, a time-out — each says why here
/// and, where there is something to do about it, offers it as [action].
class ComposerNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  /// A button at the end, or null for a notice with nothing to do.
  final String? actionLabel;
  final VoidCallback? onAction;

  const ComposerNotice({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: themeState.bgTertiary,
          borderRadius: BorderRadius.circular(K.radiusCard),
          border: Border.all(color: themeState.borderElevated),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(icon, size: K.iconRow, color: themeState.textTertiary),
            Expanded(
              child: Text(
                text,
                style: AppText.meta.copyWith(color: themeState.textSecondary),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: themeState.primary,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  actionLabel,
                  style: AppText.meta.copyWith(
                    fontWeight: FontWeight.w600,
                    color: themeState.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
