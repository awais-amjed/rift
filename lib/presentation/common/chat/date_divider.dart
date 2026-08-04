import 'package:flutter/material.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../theme/app_text.dart';

/// A centred day label with hairline rules on either side, inserted into the
/// message list whenever the calendar date changes.
class DateDivider extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  const DateDivider({super.key, required this.label, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        spacing: 12,
        children: [
          Expanded(child: Divider(color: themeState.borderPrimary, height: 1)),
          Text(
            label.toUpperCase(),
            // Mono, because a date is a figure — and it keeps the divider's
            // label visually distinct from the message text either side.
            style: AppText.meta.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
              color: themeState.textQuaternary,
            ),
          ),
          Expanded(child: Divider(color: themeState.borderPrimary, height: 1)),
        ],
      ),
    );
  }
}
