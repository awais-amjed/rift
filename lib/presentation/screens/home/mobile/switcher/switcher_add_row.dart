import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'switcher_row.dart';

/// Joining or making a server — the rail's dashed "+", at the end of the list
/// it adds to.
class SwitcherAddRow extends StatelessWidget {
  final VoidCallback onTap;

  const SwitcherAddRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: theme.borderElevated),
          ),
          child: Row(
            spacing: 11,
            children: [
              Container(
                width: SwitcherRow.leadingSize,
                height: SwitcherRow.leadingSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(K.radiusRow),
                  border: Border.all(color: theme.borderElevated),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: K.iconLarge,
                  color: theme.accentBright,
                ),
              ),
              Expanded(
                child: Text(
                  'Join or create a server',
                  style: AppText.row.copyWith(color: theme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
