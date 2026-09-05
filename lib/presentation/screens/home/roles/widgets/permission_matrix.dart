import 'package:flutter/material.dart';

import '../../../../../data/enums/server_permission.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Every permission a role can carry, grouped by where it is exercised.
///
/// Each row spends a line on what the permission actually lets somebody *do*,
/// because a name alone does not say it: "Manage channels" does not tell you
/// whether that reaches inside a private one, and the answer — it does not — is
/// the whole reason somebody would tick it.
///
/// `ADMINISTRATOR` dims the rest rather than hiding them. It implies every
/// other bit, so the boxes below it stop meaning anything; a list that vanished
/// would leave somebody wondering what they had just agreed to.
class PermissionMatrix extends StatelessWidget {
  final int permissions;

  /// Null for a role the viewer may look at but not change — the baseline role
  /// on a server where they hold nothing, or any role above their own.
  final void Function(ServerPermission permission, bool value)? onChanged;

  /// What the *viewer* holds. A permission they lack is shown and refused:
  /// hiding it would suggest it does not exist, and the subset rule is easier
  /// to obey once you can see what it is stopping you doing.
  final int viewerPermissions;

  const PermissionMatrix({
    super.key,
    required this.permissions,
    required this.viewerPermissions,
    this.onChanged,
  });

  bool get _isAdmin => permissions.carries(ServerPermission.administrator);

  bool _mayGrant(ServerPermission permission) =>
      viewerPermissions.has(permission);

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in PermissionGroup.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              group.label.toUpperCase(),
              style: AppText.sectionLabel.copyWith(
                color: themeState.textTertiary,
              ),
            ),
          ),
          for (final permission in ServerPermission.inGroup(group))
            _PermissionRow(
              permission: permission,
              // The literal bit, not the implied one: a checkbox has to show
              // what the role carries, or turning ADMINISTRATOR off would
              // leave every other box ticked and none of them real.
              value: permissions.carries(permission),
              // Dimmed under ADMINISTRATOR, which already grants them.
              implied: _isAdmin && permission != ServerPermission.administrator,
              onChanged: onChanged == null || !_mayGrant(permission)
                  ? null
                  : (v) => onChanged!(permission, v),
            ),
        ],
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final ServerPermission permission;
  final bool value;
  final bool implied;
  final ValueChanged<bool>? onChanged;

  const _PermissionRow({
    required this.permission,
    required this.value,
    required this.implied,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Opacity(
      opacity: implied ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    permission.label,
                    style: AppText.row.copyWith(color: themeState.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    permission.description,
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Opacity(
              opacity: onChanged == null ? 0.5 : 1,
              child: AppSwitch(
                value: value || implied,
                onChanged: implied ? null : onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
