import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Which role, if any, the link hands out.
///
/// Only roles the minter outranks are offered — the policy refuses the rest,
/// and an option that always fails is worse than no option. That is the same
/// rule as "an invite can never carry more than its maker holds", which is what
/// three booleans used to say.
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
              label: 'No role',
            ),
            for (final role in roles)
              _Option(
                selected: selectedId == role.id,
                onTap: onSelected == null ? null : () => onSelected!(role.id),
                label: role.name,
                // The role's own colour as a dot, the way the roles page
                // marks it, so the choice still says which role it is.
                dot: role.displayColor ?? themeState.textQuaternary,
              ),
          ],
        ),
      ],
    );
  }
}

/// One choice, drawn as the expiry and use-count choices above it are: a
/// pill with a word in it. It used to be a square with a role chip inside —
/// a tag where a choice belonged, in a second shape one row down from the
/// first.
class _Option extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final String label;
  final Color? dot;

  const _Option({
    required this.selected,
    required this.label,
    this.dot,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colour = dot;
    return SelectableSurface(
      selected: selected,
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusPill),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (colour != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          Text(
            label,
            style: selected
                ? AppText.secondaryStrong
                : AppText.secondary.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
