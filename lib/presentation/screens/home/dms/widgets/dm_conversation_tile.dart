import 'package:flutter/material.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/notification_level.dart';
import '../../../../../logic/services/conversation_time.dart';
import '../../../../common/context_menu/context_menu_button.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/hover_builder.dart';
import '../../../../common/notifications/notification_level_submenu.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/unread_badge.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// One conversation in the Home panel: who it's with, and what was last said.
///
/// Led by the person's avatar rather than a tier icon — you pick a
/// conversation by remembering the human, and which tier it is already shows
/// in the section it sits under.
class DmConversationTile extends StatelessWidget {
  final DmConversation conversation;
  final bool isSelected;
  final VoidCallback onTap;

  /// Unread messages from this peer. Passed in rather than read from a cubit
  /// because the two tiers count differently — server DMs have `notifications`
  /// rows, central DMs don't (yet) — and the tile serves both.
  final int unreadCount;

  /// How much this conversation may interrupt. Passed in for the same reason
  /// [unreadCount] is: the two tiers keep it in different places, and the tile
  /// serves both.
  final NotificationLevel level;

  /// Called when the user picks a level from the right-click menu. Null means
  /// no menu at all — a tier that has nowhere to store the answer should not
  /// offer the question.
  final ValueChanged<NotificationLevel>? onLevelChanged;

  /// Extra rows under Notifications — accept, decline, unfriend, block.
  ///
  /// Passed in as built widgets rather than as a state and four callbacks,
  /// because friendship is a central concept and this tile also serves server
  /// DMs, where membership is the relationship and there is nothing here to
  /// offer. An empty list is that tier saying so.
  final List<Widget> menuItems;

  /// Whether the peer is online, for the dot on their avatar. Null draws no
  /// dot — a tier that doesn't know shouldn't guess.
  final bool? isOnline;

  const DmConversationTile({
    super.key,
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    this.unreadCount = 0,
    this.level = NotificationLevel.dmDefault,
    this.onLevelChanged,
    this.menuItems = const [],
    this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final onLevelChanged = this.onLevelChanged;
    if (onLevelChanged == null && menuItems.isEmpty) {
      return _tile(context, null, false);
    }
    final menu = _menu(onLevelChanged);
    return ContextMenuRegion(
      contextMenu: menu,
      child: HoverBuilder(
        builder: (context, hovered) => _tile(context, menu, hovered),
      ),
    );
  }

  Widget _menu(ValueChanged<NotificationLevel>? onLevelChanged) {
    return Builder(
      builder: (context) => ContextMenuPanel(
        heading: 'Conversation',
        subheading: conversation.peerName,
        leading: SquircleAvatar(
          name: conversation.peerName,
          seed: conversation.peerId,
          size: 18,
        ),
        children: [
          if (onLevelChanged != null)
            NotificationLevelSubmenu(
              current: level,
              // No `mentions`: there is nobody else in a conversation to be
              // named among, so it would be a third button that behaved
              // exactly like the first.
              choices: NotificationLevel.dmChoices,
              onSelected: (next) {
                ContextMenuScope.of(context)?.call();
                onLevelChanged(next);
              },
            ),
          ...menuItems,
        ],
      ),
    );
  }

  /// [menu] also opens from a ••• while the tile is hovered or open, taking
  /// the place of an unread count the way a channel row's does.
  Widget _tile(BuildContext context, Widget? menu, bool hovered) {
    final themeState = context.theme;
    // A step rounder than a channel row: this tile carries two lines and an
    // avatar, and at the row radius it reads as a cramped version of one.
    final radius = BorderRadius.circular(K.radiusRow);
    final preview = conversation.lastMessage?.text;
    final compact = context.layoutMode.isCompact;
    final showButton = menu != null && !compact;
    final sentAt = conversation.lastMessage?.sentAt;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Container(
          // A phone's row is a thumb's: taller, a bigger face, and the time
          // it last moved over the count.
          padding: EdgeInsets.symmetric(
            horizontal: 9,
            vertical: compact ? 10 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: isSelected ? themeState.channelActiveBg : null,
          ),
          child: Row(
            spacing: compact ? 12 : 10,
            children: [
              _avatar(context, compact ? 44 : 34),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      conversation.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.row.copyWith(
                        color: isSelected
                            ? themeState.channelActiveText
                            : themeState.textPrimary,
                      ),
                    ),
                    if (preview != null && preview.isNotEmpty)
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(
                          // Unread lifts the preview to body ink: the line the
                          // badge is counting is the one worth reading.
                          color: unreadCount > 0
                              ? themeState.textSecondary
                              : themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    if (sentAt != null)
                      Text(
                        formatConversationTime(sentAt, DateTime.now()),
                        style: AppText.meta.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                    if (unreadCount > 0)
                      UnreadBadge(count: unreadCount, isMuted: level.isMuted)
                    else if (level.isMuted)
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 14,
                        color: themeState.textTertiary,
                      ),
                  ],
                )
              else if (unreadCount > 0 && !(showButton && hovered))
                UnreadBadge(count: unreadCount, isMuted: level.isMuted)
              else if (level.isMuted)
                Icon(
                  Icons.notifications_off_outlined,
                  size: 14,
                  color: themeState.textTertiary,
                ),
              if (showButton)
                ContextMenuButton(menu: menu, visible: hovered || isSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, double size) {
    final avatar = SquircleAvatar(
      name: conversation.peerName,
      seed: conversation.peerId,
      size: size,
    );
    final online = isOnline;
    if (online == null) return avatar;
    final theme = context.theme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online
                  ? CustomColors.userStatusOnline
                  : theme.textQuaternary,
              shape: BoxShape.circle,
              border: Border.all(color: theme.bgSecondary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
