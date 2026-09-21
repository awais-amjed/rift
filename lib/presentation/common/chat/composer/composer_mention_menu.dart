import 'package:flutter/material.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../context_menu/context_menu_panel.dart';
import '../../user_avatar.dart';

/// The `@` menu: who is here, and what they are actually called.
///
/// Built on [ContextMenuPanel] so it is the same object as the menu that opens
/// on a right-click — same surface, same width, same rounded rows. A popover is
/// a popover; one that invented its own proportions would read as a different
/// kind of thing appearing in the same place.
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
  final void Function(ServerMember member) onSelected;

  const ComposerMentionMenu({
    super.key,
    required this.members,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ContextMenuPanel(
        // A little wider than a right-click menu, because these rows carry two
        // names rather than one label — at the default width a two-word display
        // name lost its second word to an ellipsis, which is the word that
        // tells two people apart.
        maxWidth: 268,
        children: [for (final member in members) _row(context, member)],
      ),
    );
  }

  /// Deliberately the geometry of [ContextMenuItem] — 9px radius, the same
  /// padding, the same hover — with an avatar where its icon goes.
  Widget _row(BuildContext context, ServerMember member) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: () => onSelected(member),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            spacing: 9,
            children: [
              UserAvatar(
                avatarPath: member.avatarPath,
                name: member.displayName,
                size: 20,

                seed: member.id,
              ),
              // The name somebody is reading for gets the room first; the
              // username gives way.
              Flexible(
                flex: 3,
                child: Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowQuiet.copyWith(
                    color: themeState.textSecondary,
                  ),
                ),
              ),
              // Quieter and second: it is what the message will carry, not what
              // anybody is reading for.
              Flexible(
                flex: 2,
                child: Text(
                  '@${member.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
