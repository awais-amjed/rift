import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../data/classes/participant_setting.dart';
import '../../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../common/context_menu_region.dart';
import '../../../../../../../common/hover_builder.dart';
import '../../../../../../../common/member_avatar.dart';
import '../../../../../../../theme/custom_colors.dart';
import '../../../../../../../theme/theme_context.dart';
import '../../../../../sidebar/widgets/participant_context_menu.dart';
import 'roster_row_metrics.dart';

/// A member of a voice channel you're not in — rendered from Realtime
/// presence, so we only have their name (no live mic/speaking state).
///
/// Right-clicking still opens the participant menu: local mute and volume are
/// stored per user id and applied the next time you share a voice channel, so
/// they can be set before ever meeting them in a call. The menu keys off the
/// user id since there is no LiveKit identity for someone we aren't connected
/// with. [setting] shows any stored preference so the row reflects it.
class PresenceMemberRow extends StatelessWidget {
  final PresenceUser user;
  final ParticipantSetting? setting;

  const PresenceMemberRow({super.key, required this.user, this.setting});

  @override
  Widget build(BuildContext context) {
    // The presence payload's name was captured when they tracked themselves;
    // the roster is the live one. Their own copy only stands in for someone we
    // haven't loaded yet.
    final name = context.watch<ServerMembersCubit>().state.nameFor(
      user.userId,
      user.displayName,
    );
    final menu = ParticipantContextMenu(identity: user.userId, name: name);
    return ContextMenuRegion(
      contextMenu: menu,
      child: HoverBuilder(
        builder: (context, hovered) => _buildRow(context, name, menu, hovered),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String name,
    Widget menu,
    bool hovered,
  ) {
    final themeState = context.theme;
    final isMuted = setting?.muted ?? false;

    // A tint, not an ink well: clicking a person does nothing — their profile
    // is in the menu — and the tint is what says the row has one.
    return DecoratedBox(
      decoration: BoxDecoration(color: hovered ? themeState.bgHover : null),
      child: Padding(
        padding: RosterRowMetrics.of(context).padding,
        child: Row(
          spacing: 8,
          children: [
            MemberAvatar(
              userId: user.userId,
              name: name,
              size: RosterRowMetrics.of(context).avatarSize,
            ),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RosterRowMetrics.of(context).nameStyle.copyWith(
                  fontWeight: FontWeight.w500,
                  color: themeState.textSecondary,
                ),
              ),
            ),
            // Locally muted, even though they're in another channel —
            // otherwise the mute is invisible until you next join them.
            if (isMuted)
              Icon(
                Icons.volume_off_rounded,
                size: RosterRowMetrics.of(context).iconSize + 2,
                color: CustomColors.error,
              ),
          ],
        ),
      ),
    );
  }
}
