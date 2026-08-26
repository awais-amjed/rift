import 'package:flutter/material.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/server_role.dart';
import '../../../../theme/app_text.dart';

/// A member's standing in the server: ADMIN, MOD.
///
/// Words rather than the icons this used to use — a shield and a wrench mean
/// nothing until someone tells you, and there is room on the row for the
/// letters.
///
/// `MOD` is short for the role [ServerRole.channelManager], which the Members
/// dialog and the participant menu both spell out as "Channel Manager". The
/// abbreviation is deliberate — there is room on a member row for three
/// letters and not for two words.
///
/// The one thing it does *not* cover is banning: `moderate_user` gates
/// `p_banned` on `app.is_admin()` and everything else on
/// `app.can_manage_channels()`, so a MOD may mute, deafen, disconnect, remove
/// any message and manage channels — but cannot end somebody's membership.
/// [ServerRole.channelManager] carries the full sentence.
class RoleChip extends StatelessWidget {
  final ServerRole role;
  final ThemeState themeState;

  const RoleChip({super.key, required this.role, required this.themeState});

  /// Admins get the accent; lesser roles get a neutral fill, so seniority is
  /// visible without reading.
  bool get _isPrimary => role == ServerRole.admin;

  String get _label => switch (role) {
    ServerRole.admin => 'ADMIN',
    ServerRole.channelManager => 'MOD',
    ServerRole.invites => 'INVITES',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _isPrimary
            ? themeState.primary.withValues(alpha: 0.14)
            : themeState.bgHover,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _label,
        style: AppText.roleChip.copyWith(
          color: _isPrimary ? themeState.accentBright : themeState.textTertiary,
        ),
      ),
    );
  }
}
