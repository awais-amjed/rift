import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../common/context_menu/context_menu_button.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/hover_builder.dart';
import '../../../../common/user_avatar.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../profile/person/show_person_profile.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import 'role_chip.dart';

/// One member in the right-hand sidebar: avatar, name, role/state badges.
///
/// Offline members are dimmed rather than hidden, so the list is a stable
/// roster you can right-click at any time — local mute and volume are stored
/// per user and apply the next time you share a voice channel.
class MemberRow extends StatelessWidget {
  final ServerMember member;
  final bool isOnline;
  final bool isMe;
  final ParticipantSetting? setting;

  /// The most senior role this member holds, or null — what the chip says.
  final Role? role;

  /// The most senior role that was *given a colour*, which is not always the
  /// same one. A role can carry permissions and no colour deliberately; letting
  /// it hide the colour of the role beneath it would make that choice cost
  /// something nobody intended.
  final Role? colourRole;

  const MemberRow({
    super.key,
    required this.member,
    required this.isOnline,
    this.isMe = false,
    this.setting,
    this.role,
    this.colourRole,
  });

  @override
  Widget build(BuildContext context) {
    // No point right-clicking yourself for a local mute.
    if (isMe) return _buildRow(context, null, false);
    final menu = ParticipantContextMenu(
      identity: member.id,
      name: member.displayName,
    );
    return ContextMenuRegion(
      contextMenu: menu,
      child: HoverBuilder(
        builder: (context, hovered) => _buildRow(context, menu, hovered),
      ),
    );
  }

  /// [menu] also opens from a ••• on hover — local mute and volume are in it,
  /// and nothing on the row said so.
  Widget _buildRow(BuildContext context, Widget? menu, bool hovered) {
    final themeState = context.theme;
    final locallyMuted = setting?.muted ?? false;
    // Offline members stay on the list but recede — the roster should be a
    // stable thing you can right-click, not a list that reshuffles as people
    // come and go.
    final dim = isOnline ? 1.0 : 0.4;

    return Opacity(
      opacity: dim,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          hoverColor: themeState.bgHover,
          // The row has been inert since it was written. Clicking a person is
          // the one thing everybody tries first, and until now it was the
          // right-click menu or nothing.
          onTap: () => showMemberProfile(
            context,
            userId: member.id,
            name: member.displayName,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              spacing: 9,
              children: [
                _avatar(context),
                Expanded(
                  child: Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowQuiet.copyWith(
                      // A role's colour is the point of giving it one, and the
                      // name is the only thing on this row long enough to
                      // carry it. Uncoloured roles leave the name alone.
                      color:
                          colourRole?.displayColor ?? themeState.textSecondary,
                    ),
                  ),
                ),
                ..._badges(locallyMuted),
                if (menu != null && !context.layoutMode.isCompact)
                  ContextMenuButton(menu: menu, visible: hovered),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final themeState = context.theme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(
          avatarPath: member.avatarPath,
          name: member.displayName,
          seed: member.id,
          size: 28,
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
    // One chip, not all of them. The row is already carrying a name, a
    // presence dot and up to two moderation icons; every role somebody holds
    // belongs in the members dialog, where there is room and where somebody
    // has gone looking.
    if (role case final role?) {
      badges.add(RoleChip(role: role));
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
