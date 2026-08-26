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
/// **It does not mean what "mod" means elsewhere.** A channel manager creates
/// and deletes channels, removes anyone's message, and disconnects people from
/// a call. Muting, deafening and banning are `moderate_user`, which checks
/// `app.is_admin()`, so a MOD can do none of them. The full grant is spelled
/// out in [ServerRole.channelManager] and shown wherever the role is handed
/// out; do not re-derive it from this word.
///
/// Deliberately not interactive. The label is the whole message, and a chip
/// that opens something is a chip people have to try before they know it does
/// nothing useful.
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
