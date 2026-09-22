import 'package:flutter/material.dart';

import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One fact in a profile: its name in small print over the answer.
///
/// Stacked rather than a label-left/value-right row. Those rows only look
/// like a pair while the dialog is narrow enough to hold them together; given
/// a profile's width they become a name and an answer at opposite ends of a
/// stretch of nothing, and the eye stops pairing them.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppText.label.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppText.row.copyWith(
            color: quiet ? themeState.textTertiary : themeState.textPrimary,
          ),
        ),
      ],
    );
  }
}
