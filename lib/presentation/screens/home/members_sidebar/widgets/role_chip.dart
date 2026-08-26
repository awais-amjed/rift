import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/badge_explainer.dart';
import '../../../../common/server_role.dart';
import '../../../../theme/app_text.dart';

/// A member's standing in the server: ADMIN, MANAGER.
///
/// Words rather than the icons this used to use — a shield and a wrench mean
/// nothing until someone tells you, and there is room on the row for the
/// letters.
///
/// It used to say `MOD`, which was the wrong word twice over. It implied the
/// powers people expect of a moderator — ban, mute — which a channel manager
/// does not have (those are `moderate_user`, admin-only), and it was a third
/// name for a role the Members dialog and the participant menu both call
/// "Channel Manager". [ServerRole] exists so those surfaces cannot drift; this
/// one had drifted.
///
/// **Tappable**, for the same reason the unencrypted-message badge is: a chip
/// that grants real power over a channel should be able to say what it grants,
/// on the row where you see it, without a trip to a settings dialog.
class RoleChip extends StatelessWidget {
  final ServerRole role;
  final ThemeState themeState;

  const RoleChip({super.key, required this.role, required this.themeState});

  /// Admins get the accent; lesser roles get a neutral fill, so seniority is
  /// visible without reading.
  bool get _isPrimary => role == ServerRole.admin;

  String get _label => switch (role) {
    ServerRole.admin => 'ADMIN',
    ServerRole.channelManager => 'MANAGER',
    ServerRole.invites => 'INVITES',
  };

  @override
  Widget build(BuildContext context) {
    final color = _isPrimary
        ? themeState.accentBright
        : themeState.textTertiary;

    return Builder(
      builder: (chipContext) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showBadgeExplainer(
            chipContext,
            icon: role.icon,
            iconColor: color,
            title: role.label,
            body: '${role.description}.',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _isPrimary
                  ? themeState.primary.withValues(alpha: 0.14)
                  : themeState.bgHover,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(_label, style: AppText.roleChip.copyWith(color: color)),
          ),
        ),
      ),
    );
  }
}
