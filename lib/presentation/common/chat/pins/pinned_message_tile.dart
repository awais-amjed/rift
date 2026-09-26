import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/conversation_time.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../hover_builder.dart';
import '../message_row/message_origin_badge.dart';
import '../message_row/message_row_avatar.dart';
import 'pinned_message_preview.dart';
import 'pinned_tile_action.dart';

/// One pinned message in the pinned list, laid out like the message it is —
/// avatar, name, when, and what it says — so it reads as the conversation
/// rather than as a list of cards about it. Pressing it goes to the message.
///
/// Jump and Unpin show on hover, the way a message's own toolbar does. On a
/// phone there is no hover: Unpin stays, and Jump is the row itself. An unencrypted message carries its
/// badge here as it does in the conversation (AGENTS.md, Presentation).
class PinnedMessageTile extends StatelessWidget {
  final ChatMessage message;
  final Map<String, String> displayNames;
  final VoidCallback? onJump;

  /// Take the pin down. Null where the reader may not.
  final VoidCallback? onUnpin;

  const PinnedMessageTile({
    super.key,
    required this.message,
    this.displayNames = const {},
    this.onJump,
    this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final touch = context.layoutMode.isCompact;
    final radius = BorderRadius.circular(K.radiusRow);
    return HoverBuilder(
      builder: (context, hovered) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          hoverColor: themeState.bgHover,
          onTap: onJump,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                SizedBox(
                  width: K.messageGutter,
                  child: MessageRowAvatar(
                    authorName: message.authorName,
                    authorId: message.authorId,
                    avatarPath: message.authorAvatarPath,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      _header(context, touch: touch, hovered: hovered),
                      PinnedMessagePreview(
                        message: message,
                        displayNames: displayNames,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required bool touch,
    required bool hovered,
  }) {
    final themeState = context.theme;
    // On a phone the row itself is the way to the message, so a Jump on every
    // row would be one more button saying what tapping already does.
    final actions = [
      if (onJump != null && !touch)
        PinnedTileAction(label: 'Jump', onPressed: onJump),
      if (onUnpin != null) PinnedTileAction(label: 'Unpin', onPressed: onUnpin),
    ];
    final show = touch || hovered;
    return SizedBox(
      // The buttons are taller than the name; fixing the line's height keeps
      // the text from jumping when they appear under the pointer.
      height: 22,
      child: Row(
        spacing: 8,
        children: [
          // Everything but the buttons shares one Expanded, so the buttons sit
          // on the right edge of every row rather than wherever a name ends.
          Expanded(
            child: Row(
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    message.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.strong.copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                // The conversation badges a message the server could read,
                // always, and so does every other place that shows one.
                if (MessageOriginBadge.isNeededFor(message))
                  MessageOriginBadge(message: message),
                Text(
                  formatMessageMoment(message.sentAt, DateTime.now()),
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: AppMotion.react,
              child: IgnorePointer(
                ignoring: !show,
                child: Row(spacing: 6, children: actions),
              ),
            ),
        ],
      ),
    );
  }
}
