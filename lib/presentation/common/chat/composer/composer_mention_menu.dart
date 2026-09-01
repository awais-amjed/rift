import 'package:flutter/material.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../popover_surface.dart';
import '../../user_avatar.dart';

/// The `@` menu: who is here, and what they are actually called.
///
/// Two names on every row, and both earn their place. The **display name** is
/// what somebody is looking for — it is the name they see in the room and the
/// one they were about to type. The **username** is what the message will
/// contain, because display names can be changed by their owner and can
/// collide, so a mention resolves against the username or it resolves against
/// the wrong person.
///
/// Showing only the first would leave people typing a name that goes nowhere;
/// showing only the second is the problem this menu exists to fix.
class ComposerMentionMenu extends StatelessWidget {
  final List<ServerMember> members;
  final ThemeState themeState;
  final void Function(ServerMember member) onSelected;

  const ComposerMentionMenu({
    super.key,
    required this.members,
    required this.themeState,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: PopoverSurface(
        child: ConstrainedBox(
          // Deliberately short: it floats over the conversation, so every row
          // covers a line of what somebody just said, and the answer is nearly
          // always in the first two.
          //
          // Tall enough for [MentionSuggestions.maxResults] whole rows. A
          // ceiling that cut the last one in half read as a rendering bug
          // rather than as a list that continues.
          constraints: const BoxConstraints(maxHeight: 152),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: members.length,
            itemBuilder: (context, i) => _row(members[i]),
          ),
        ),
      ),
    );
  }

  Widget _row(ServerMember member) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onSelected(member),
        hoverColor: themeState.bgHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            spacing: 8,
            children: [
              UserAvatar(
                avatarPath: member.avatarPath,
                name: member.displayName,
                size: 22,
                themeState: themeState,
                seed: member.id,
              ),
              Flexible(
                child: Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(
                    fontWeight: FontWeight.w600,
                    color: themeState.textPrimary,
                  ),
                ),
              ),
              Text(
                '@${member.username}',
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
              const Spacer(),
              if (member.isBot)
                Text(
                  'BOT',
                  style: AppText.sectionLabel.copyWith(
                    letterSpacing: 0.6,
                    color: themeState.textQuaternary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
