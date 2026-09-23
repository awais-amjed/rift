import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../members_sidebar/widgets/role_chip.dart';

/// Which role, if any, the link hands out.
///
/// Only roles the minter outranks are offered — the policy refuses the rest,
/// and an option that always fails is worse than no option. That is the same
/// rule as "an invite can never carry more than its maker holds", which is what
/// three booleans used to say (`008_role_management.sql`).
///
/// "No role" is first and selected by default. Handing somebody a role by link
/// is the deliberate case; joining as an ordinary member is the common one.
class InviteRolePicker extends StatelessWidget {
  final List<Role> roles;
  final String? selectedId;
  final ValueChanged<String?>? onSelected;

  const InviteRolePicker({
    super.key,
    required this.roles,
    required this.selectedId,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    if (roles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GIVE THEM A ROLE',
          style: AppText.sectionLabel.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Option(
              selected: selectedId == null,
              onTap: onSelected == null ? null : () => onSelected!(null),
              child: Text(
                'No role',
                style: AppText.secondary.copyWith(
                  color: themeState.textSecondary,
                ),
              ),
            ),
            for (final role in roles)
              _Option(
                selected: selectedId == role.id,
                onTap: onSelected == null ? null : () => onSelected!(role.id),
                // The picker wraps, so there is no row for a long name to
                // push anything off — the sidebar's eight characters turned
                // the stock "Moderator" into "MODERAT…" in a dialog with
                // room for three of it.
                child: RoleChip(role: role, maxChars: RoleChip.wide),
              ),
          ],
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  const _Option({required this.selected, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SelectableSurface(
      selected: selected,
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: child,
    );
  }
}
