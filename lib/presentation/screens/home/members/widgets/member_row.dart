import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/role_ladder.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../members_sidebar/widgets/role_chip.dart';
import '../../../../common/label_pill.dart';
import 'member_badge.dart';
import 'member_manage_panel.dart';
import '../../../../../data/constants.dart';

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

  /// Every role this member holds, most senior first. This is the screen with
  /// room for all of them — the sidebar shows one, because a row there is
  /// already carrying a name, a presence dot and two moderation icons.
  final List<Role> roles;
  final VoidCallback onTap;
  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;

  const MemberRow({
    super.key,
    required this.member,
    required this.isSelf,
    required this.isExpanded,
    required this.isBusy,
    required this.canManagePermissions,
    required this.canModerate,
    this.roles = const [],
    required this.onTap,
    required this.onModerate,
  });

  bool get _expandable => canManagePermissions || canModerate;

  /// What actually earns a chip — see [RoleLadder.badges].
  List<Role> get _badges => RoleLadder.badges(roles);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          children: [
            Material(
              color: isExpanded ? themeState.bgSecondary : Colors.transparent,
              borderRadius: BorderRadius.circular(K.radiusRow),
              child: InkWell(
                borderRadius: BorderRadius.circular(K.radiusRow),
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
                                color: themeState.textPrimary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '@${member.username}',
                              style: AppText.secondary.copyWith(
                                color: themeState.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // The roles by name, not two icons standing in for the
                      // three flags the old model had. A shield told you
                      // somebody was an admin and nothing about the role
                      // somebody actually made.
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final role in _badges.take(3))
                            RoleChip(role: role, themeState: themeState),
                          if (_badges.length > 3)
                            Text(
                              '+${_badges.length - 3}',
                              style: AppText.meta.copyWith(
                                color: themeState.textTertiary,
                              ),
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
                          // This is the one list a banned member appears in,
                          // and the only place a ban can be lifted; the row
                          // has to say so.
                          if (member.isBanned)
                            LabelPill(
                              label: 'Banned',
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
                onModerate: onModerate,
              ),
          ],
        );
      },
    );
  }
}
