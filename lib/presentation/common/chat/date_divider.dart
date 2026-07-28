import 'package:flutter/material.dart';

import '../../../logic/cubits/theme/theme_cubit.dart';

/// A centred day label with hairline rules on either side, inserted into the
/// message list whenever the calendar date changes.
class DateDivider extends StatelessWidget {
  final String label;
  final ThemeState themeState;

  const DateDivider({super.key, required this.label, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: themeState.borderPrimary, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: themeState.textQuaternary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: themeState.borderPrimary, height: 1)),
        ],
      ),
    );
  }
}
