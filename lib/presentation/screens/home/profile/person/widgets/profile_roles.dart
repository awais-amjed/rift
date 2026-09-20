import 'package:flutter/material.dart';

import '../../../../../../data/classes/role.dart';
import '../../../../../common/label_pill.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Every role a member holds, most senior first.
///
/// Every one of them, unlike the single truncated chip on a sidebar row —
/// this is the screen that row's chip points at, and a profile that showed
/// the same one role would be the trip for nothing. Names are given in full
/// for the same reason: there is room here, and a role's name is whoever made
/// it's to choose.
class ProfileRoles extends StatelessWidget {
  final List<Role> roles;

  const ProfileRoles({super.key, required this.roles});

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) {
      return Text(
        'No roles',
        style: AppText.secondary.copyWith(color: context.theme.textTertiary),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final role in roles)
          LabelPill(label: role.name, color: role.displayColor),
      ],
    );
  }
}
