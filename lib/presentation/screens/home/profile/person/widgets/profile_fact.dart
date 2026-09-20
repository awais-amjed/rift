import 'package:flutter/material.dart';

import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One "name: answer" line in a profile.
///
/// The answer is always given, never left blank — a fact with an empty right
/// half reads as a field that failed to load. Where there is nothing to say,
/// the caller passes the sentence that says so ("Not set up yet"), and marks
/// it [quiet] so it recedes instead of looking like a value.
class ProfileFact extends StatelessWidget {
  final String label;
  final String value;

  /// Draws the answer in the tertiary ink: for an absence, not a value.
  final bool quiet;

  const ProfileFact({
    super.key,
    required this.label,
    required this.value,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.secondary.copyWith(
                color: quiet
                    ? themeState.textTertiary
                    : themeState.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
