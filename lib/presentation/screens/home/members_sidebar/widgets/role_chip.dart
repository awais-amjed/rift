import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';

/// A member's most senior role, beside their name.
///
/// Words rather than icons — a shield and a wrench mean nothing until somebody
/// tells you, and there is room on the row for the letters.
///
/// It shows **one** role, not all of them. A member row is already carrying a
/// name, a presence dot and up to two moderation icons; a list of every role
/// somebody holds belongs in the members dialog, where there is room for it and
/// where somebody has gone looking.
///
/// Uppercased, and cut to eight characters. A role's name is whoever made it's
/// to choose and can be anything; a chip that grew with it would push the name
/// it is annotating off the row.
class RoleChip extends StatelessWidget {
  final Role role;
  final ThemeState themeState;

  const RoleChip({super.key, required this.role, required this.themeState});

  String get _label {
    final name = role.name.trim().toUpperCase();
    return name.length <= 8 ? name : '${name.substring(0, 7)}…';
  }

  @override
  Widget build(BuildContext context) {
    // A role that was given no colour is drawn in the neutral fill this chip
    // has always used, rather than being invented one: leaving it uncoloured is
    // a choice somebody made in the editor.
    final colour = role.displayColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colour == null
            ? themeState.bgHover
            : colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _label,
        style: AppText.roleChip.copyWith(
          color: colour ?? themeState.textTertiary,
        ),
      ),
    );
  }
}
