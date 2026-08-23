import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/custom_colors.dart';
import 'member_badge.dart';
import 'member_manage_panel.dart';
import '../../../../theme/app_text.dart';

/// One member in the members dialog: avatar, names, permission/moderation
/// badges — expandable into a [MemberManagePanel] when the viewer may manage
/// this member.
class MemberRow extends StatelessWidget {
  final ServerMember member;
  final bool isSelf;
  final bool isExpanded;
  final bool isBusy;
  final bool canManagePermissions;
  final bool canModerate;
  final VoidCallback onTap;
  final void Function({
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  })
  onPermissionChanged;
  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;

  const MemberRow({
    super.key,
    required this.member,
    required this.isSelf,
    required this.isExpanded,
    required this.isBusy,
    required this.canManagePermissions,
    required this.canModerate,
    required this.onTap,
    required this.onPermissionChanged,
    required this.onModerate,
  });

  bool get _expandable => canManagePermissions || canModerate;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          children: [
            Material(
              color: isExpanded ? themeState.bgSecondary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                hoverColor: themeState.bgHover,
                onTap: _expandable ? onTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // The shared avatar, not a hand-rolled circle: this was
                      // the last place drawing an initial on flat grey, which
                      // made the same person unrecognisable between here and
                      // the members panel — and it ignored uploaded pictures
                      // entirely.
                      UserAvatar(
                        avatarPath: member.avatarPath,
                        name: member.displayName,
                        seed: member.id,
                        size: 30,
                        themeState: themeState,
                      ),
                      const SizedBox(width: 10),
                      // Names
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSelf
                                  ? '${member.displayName} (You)'
                                  : member.displayName,
                              style: AppText.row.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: themeState.textPrimary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '@${member.username}',
                              style: AppText.label.copyWith(
                                fontSize: 11,
                                color: themeState.textQuaternary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badges
                      Wrap(
                        spacing: 4,
                        children: [
                          if (member.permissions.isServerAdmin)
                            MemberBadge(
                              icon: Icons.shield_outlined,
                              tooltip: 'Server Admin',
                              color: themeState.primary,
                              themeState: themeState,
                            ),
                          if (member.permissions.isChannelManager)
                            MemberBadge(
                              icon: Icons.tune_outlined,
                              tooltip: 'Channel Manager',
                              color: themeState.textSecondary,
                              themeState: themeState,
                            ),
                          if (member.isMuted)
                            MemberBadge(
                              icon: Icons.mic_off,
                              tooltip: 'Muted by a moderator',
                              color: CustomColors.error,
                              themeState: themeState,
                            ),
                          if (member.isDeafened)
                            MemberBadge(
                              icon: Icons.headset_off,
                              tooltip: 'Deafened by a moderator',
                              color: CustomColors.error,
                              themeState: themeState,
                            ),
                        ],
                      ),
                      if (_expandable) ...[
                        const SizedBox(width: 6),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: themeState.textQuaternary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (isExpanded && _expandable)
              MemberManagePanel(
                member: member,
                isBusy: isBusy,
                canManagePermissions: canManagePermissions,
                canModerate: canModerate,
                onPermissionChanged: onPermissionChanged,
                onModerate: onModerate,
              ),
          ],
        );
      },
    );
  }
}
