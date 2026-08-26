import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/app_text.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import '../../../../common/server_role.dart';
import 'role_chip.dart';

/// One member in the right-hand sidebar: avatar, name, role/state badges.
///
/// Offline members are dimmed rather than hidden, so the list is a stable
/// roster you can right-click at any time — local mute and volume are stored
/// per user and apply the next time you share a voice channel.
class MemberRow extends StatelessWidget {
  final ServerMember member;
  final ThemeState themeState;
  final bool isOnline;
  final bool isMe;
  final ParticipantSetting? setting;

  const MemberRow({
    super.key,
    required this.member,
    required this.themeState,
    required this.isOnline,
    this.isMe = false,
    this.setting,
  });

  @override
  Widget build(BuildContext context) {
    final row = _buildRow();
    // No point right-clicking yourself for a local mute.
    if (isMe) return row;
    return ContextMenuRegion(
      contextMenu: ParticipantContextMenu(
        identity: member.id,
        name: member.displayName,
      ),
      child: row,
    );
  }

  Widget _buildRow() {
    final locallyMuted = setting?.muted ?? false;
    // Offline members stay on the list but recede — the roster should be a
    // stable thing you can right-click, not a list that reshuffles as people
    // come and go.
    final dim = isOnline ? 1.0 : 0.4;

    return Opacity(
      opacity: dim,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: themeState.bgHover,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              spacing: 9,
              children: [
                _avatar(),
                Expanded(
                  child: Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowQuiet.copyWith(
                      fontSize: 13,
                      color: themeState.textSecondary,
                    ),
                  ),
                ),
                ..._badges(locallyMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(
          avatarPath: member.avatarPath,
          name: member.displayName,
          seed: member.id,
          size: 28,
          themeState: themeState,
        ),
        // Presence dot, ringed in the panel colour so it reads as a cut-out.
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: isOnline
                  ? CustomColors.userStatusOnline
                  : themeState.textQuaternary,
              shape: BoxShape.circle,
              border: Border.all(color: themeState.bgSecondary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _badges(bool locallyMuted) {
    final badges = <Widget>[];
    // One chip, not two: an admin holds everything a manager does, so showing
    // both would read as two grants rather than one that subsumes the other.
    if (member.permissions.isServerAdmin) {
      badges.add(RoleChip(role: ServerRole.admin, themeState: themeState));
    } else if (member.permissions.isChannelManager) {
      badges.add(
        RoleChip(role: ServerRole.channelManager, themeState: themeState),
      );
    }
    if (member.isMuted) {
      badges.add(
        const Icon(Icons.mic_off_rounded, size: 13, color: CustomColors.error),
      );
    }
    if (locallyMuted) {
      badges.add(
        const Icon(
          Icons.volume_off_rounded,
          size: 13,
          color: CustomColors.error,
        ),
      );
    }
    return badges;
  }
}
