import 'package:flutter/material.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/unread_badge.dart';
import '../../../../theme/app_text.dart';

/// One conversation in the Home panel: who it's with, and what was last said.
///
/// Led by the person's avatar rather than a tier icon — you pick a
/// conversation by remembering the human, and which tier it is already shows
/// in the section it sits under.
class DmConversationTile extends StatelessWidget {
  final DmConversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeState themeState;

  /// Unread messages from this peer. Passed in rather than read from a cubit
  /// because the two tiers count differently — server DMs have `notifications`
  /// rows, central DMs don't (yet) — and the tile serves both.
  final int unreadCount;

  const DmConversationTile({
    super.key,
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.themeState,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // A step rounder than a channel row: this tile carries two lines and an
    // avatar, and at the row radius it reads as a cramped version of one.
    final radius = BorderRadius.circular(K.radiusButton);
    final preview = conversation.lastMessage?.text;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: isSelected ? themeState.activeRowGradient : null,
            border: isSelected
                ? Border.all(color: themeState.channelActiveBorder)
                : null,
          ),
          child: Row(
            spacing: 10,
            children: [
              SquircleAvatar(
                name: conversation.peerName,
                seed: conversation.peerId,
                size: 34,
              ),
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
                        fontSize: 13,
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
                          fontSize: 11.5,
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
              if (unreadCount > 0)
                UnreadBadge(count: unreadCount, themeState: themeState),
            ],
          ),
        ),
      ),
    );
  }
}
