import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/permission_toggle.dart';
import '../../../../theme/custom_colors.dart';

/// Expanded management controls under a member row: permission toggles
/// (server admins only) and mute/deafen moderation buttons (admins and
/// channel managers).
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
  final void Function({bool? muted, bool? deafened}) onModerate;

  const MemberManagePanel({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canManagePermissions,
    required this.canModerate,
    required this.onPermissionChanged,
    required this.onModerate,
  });

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
              if (canManagePermissions) ...[
                PermissionToggle(
                  icon: Icons.shield_outlined,
                  label: 'Server Admin',
                  description: 'Full server management access',
                  value: member.permissions.isServerAdmin,
                  onChanged: isBusy
                      ? null
                      : (v) => onPermissionChanged(isServerAdmin: v),
                  themeState: themeState,
                  isFirst: true,
                ),
                PermissionToggle(
                  icon: Icons.tune_outlined,
                  label: 'Channel Manager',
                  description: 'Create channels and moderate members',
                  value: member.permissions.isChannelManager,
                  onChanged: isBusy
                      ? null
                      : (v) => onPermissionChanged(isChannelManager: v),
                  themeState: themeState,
                  isFirst: false,
                ),
                PermissionToggle(
                  icon: Icons.link_outlined,
                  label: 'Can Invite',
                  description: 'Allowed to generate invite codes',
                  value: member.permissions.canCreateTokens,
                  onChanged: isBusy
                      ? null
                      : (v) => onPermissionChanged(canCreateTokens: v),
                  themeState: themeState,
                  isFirst: false,
                ),
              ],
              if (canModerate) ...[
                if (canManagePermissions)
                  Divider(height: 1, color: themeState.borderPrimary),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ModerationButton(
                          icon: member.isMuted ? Icons.mic : Icons.mic_off,
                          label: member.isMuted ? 'Unmute' : 'Server Mute',
                          isActive: member.isMuted,
                          themeState: themeState,
                          onTap: isBusy
                              ? null
                              : () => onModerate(muted: !member.isMuted),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ModerationButton(
                          icon: member.isDeafened
                              ? Icons.headset
                              : Icons.headset_off,
                          label: member.isDeafened
                              ? 'Undeafen'
                              : 'Server Deafen',
                          isActive: member.isDeafened,
                          themeState: themeState,
                          onTap: isBusy
                              ? null
                              : () => onModerate(deafened: !member.isDeafened),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModerationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ThemeState themeState;
  final VoidCallback? onTap;

  const _ModerationButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.themeState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? themeState.textSecondary : CustomColors.error;

    return Material(
      color: isActive
          ? Colors.transparent
          : CustomColors.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
