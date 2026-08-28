import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/permission_toggle.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/server_role.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../roles/member_roles_dialog.dart';
import 'member_moderation_row.dart';

/// Expanded management controls under a member row: permission toggles
/// (server admins only), mute/deafen moderation buttons (admins and channel
/// managers), and the ban control.
///
/// This is the only place a ban can be *lifted*. The participant context menu
/// can ban, but it only ever sees people who are connected, and a banned
/// member cannot be — so a toggle there would be a constant. Here the row
/// comes from the member list, which carries the real flag either way.
class MemberManagePanel extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canManagePermissions;
  final bool canModerate;
  final void Function({
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  })
  onPermissionChanged;
  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;

  const MemberManagePanel({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canManagePermissions,
    required this.canModerate,
    required this.onPermissionChanged,
    required this.onModerate,
  });

  /// Bans ask first; lifting one doesn't.
  ///
  /// The asymmetry is the point — a ban cuts someone off mid-sentence and an
  /// unban only gives that back, so only one of the two is worth a speed bump.
  Future<void> _toggleBan(BuildContext context) async {
    if (member.isBanned) {
      onModerate(banned: false);
      return;
    }
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Ban ${member.displayName}?',
      message:
          'They lose access to this server immediately, including anything '
          'they are in the middle of. Their messages stay, and you can lift '
          'this again from here.',
      confirmLabel: 'Ban',
      icon: Icons.gavel_rounded,
      isDestructive: true,
    );
    if (confirmed) onModerate(banned: true);
  }

  /// `set_user_permissions` takes the three as separate nullable booleans, so
  /// the role picks which one to fill and the compiler checks the rest.
  void _grant(ServerRole role, bool value) {
    switch (role) {
      case ServerRole.admin:
        onPermissionChanged(isServerAdmin: value);
      case ServerRole.channelManager:
        onPermissionChanged(isChannelManager: value);
      case ServerRole.invites:
        onPermissionChanged(canCreateTokens: value);
    }
  }

  void _openRoles(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: MemberRolesDialog(member: member),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Column(
            children: [
              if (canManagePermissions)
                for (final role in ServerRole.values)
                  PermissionToggle(
                    icon: role.icon,
                    label: role.label,
                    description: role.description,
                    value: role.isHeldBy(member.permissions),
                    onChanged: isBusy ? null : (v) => _grant(role, v),
                    themeState: themeState,
                    isFirst: role == ServerRole.values.first,
                  ),
              // The three toggles above are the old shape of this, kept
              // because they are the three most servers ever use. Anything
              // else — a custom role, one of the other nineteen permissions —
              // is behind this, which is where roles actually live now.
              if (canManagePermissions) ...[
                Divider(height: 1, color: themeState.borderPrimary),
                InkWell(
                  onTap: isBusy ? null : () => _openRoles(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      spacing: 9,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: themeState.textTertiary,
                        ),
                        Expanded(
                          child: Text(
                            'Roles',
                            style: TextStyle(color: themeState.textPrimary),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: themeState.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              MemberModerationRow(
                member: member,
                themeState: themeState,
                isBusy: isBusy,
                canModerate: canModerate,
                canBan: canManagePermissions,
                dividerAbove: canManagePermissions,
                onModerate: onModerate,
                onToggleBan: () => _toggleBan(context),
              ),
            ],
          ),
        );
      },
    );
  }
}
