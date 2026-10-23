import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/server_scope.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/member_card/member_card_anchor.dart';
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/member_card/member_card_layout.dart';
import '../../channels/open_voice_channel.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import 'role_chip.dart';

/// Over the widget budget and one job: one row of the member sidebar.
///
/// One member in the right-hand sidebar: avatar, name, role/state badges.
///
/// Offline members are dimmed rather than hidden, so the list is a stable
/// roster you can right-click at any time — local mute and volume are stored
/// per user and apply the next time you share a voice channel.
class MemberRow extends StatelessWidget {
  final ServerMember member;

  /// Null until presence has answered: drawn at full strength with no dot,
  /// since dimming somebody says they are offline, which nobody knows yet.
  final bool? isOnline;
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
    // Your own row gets the menu too — it is the way to your own profile —
    // in its "You" form, which offers nothing aimed at somebody else.
    final menu = ParticipantContextMenu(
      identity: member.id,
      name: member.displayName,
      isLocal: isMe,
    );
    return ContextMenuRegion(
      contextMenu: menu,
      // The card a voice channel's rows open, from the other side: it looks
      // up which call they are in, and opens to the left, over the page.
      child: MemberCardAnchor(
        userId: member.id,
        name: member.displayName,
        side: MemberCardSide.left,
        onWatch: (channelId) => _watch(context, channelId),
        builder: (open) => _buildRow(context, open),
      ),
    );
  }

  /// Into the call they are sharing in, and onto their stream.
  void _watch(BuildContext context, String channelId) {
    final channel = context
        .read<ServerCubit>()
        .state
        .serverOn(ServerScope.readId(context))
        ?.channels
        .where((ch) => ch.id == channelId)
        .firstOrNull;
    if (channel == null) return;
    unawaited(watchStreamIn(context, channel, member.id));
  }

  Widget _buildRow(BuildContext context, VoidCallback openCard) {
    final themeState = context.theme;
    final locallyMuted = setting?.muted ?? false;
    // Offline members stay on the list but recede — the roster should be a
    // stable thing you can right-click, not a list that reshuffles as people
    // come and go.
    final dim = isOnline == false ? 0.4 : 1.0;

    return Opacity(
      opacity: dim,
      // A well, because clicking a person opens their card — their profile
      // is a click on its avatar. It used to do nothing at all: the profile
      // was in the right-click menu and the row did not even change the
      // cursor, so there was nothing to say the row was live.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          hoverColor: themeState.bgHover,
          onTap: openCard,
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
        if (isOnline != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: isOnline!
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
        const Icon(
          Icons.mic_off_rounded,
          size: K.iconInline,
          color: CustomColors.error,
        ),
      );
    }
    if (locallyMuted) {
      badges.add(
        const Icon(
          Icons.volume_off_rounded,
          size: K.iconInline,
          color: CustomColors.error,
        ),
      );
    }
    return badges;
  }
}
