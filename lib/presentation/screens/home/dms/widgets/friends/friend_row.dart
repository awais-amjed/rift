import 'package:flutter/material.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/constants.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import 'friend_action_button.dart';
import 'friend_row_action.dart';

/// One person in the friends page: who they are, where things stand, and what
/// can be done about it.
///
/// The same row for all four lists. What differs between a friend, a request
/// and a block is [note] and [actions], and passing those in is what keeps
/// this from becoming a switch over the state with four layouts inside it.
class FriendRow extends StatelessWidget {
  final Friend friend;

  /// The quiet second line — "Sent you a message request", "Waiting for them".
  /// Null for a friend, where the handle says everything there is to say.
  final String? note;

  final List<FriendRowAction> actions;

  /// Opens the conversation. Null for rows that do not lead anywhere: you
  /// cannot type at somebody you have blocked.
  final VoidCallback? onTap;

  /// Opens their profile — from the picture, not the row.
  ///
  /// The row already means "talk to them", which is the thing people came to
  /// this page to do; taking that over would cost a press to gain one. The
  /// avatar is where Discord puts it and the only part of the row that is
  /// about the person rather than the conversation. It is also the only way
  /// in on a blocked or pending row, where [onTap] is null.
  final VoidCallback? onOpenProfile;

  const FriendRow({
    super.key,
    required this.friend,
    this.note,
    this.actions = const [],
    this.onTap,
    this.onOpenProfile,
  });

  Widget _avatar() {
    final avatar = SquircleAvatar(
      name: friend.handle,
      seed: friend.id,
      size: 34,
    );
    final open = onOpenProfile;
    if (open == null) return avatar;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: open, child: avatar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            spacing: 11,
            children: [
              _avatar(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@${friend.handle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.row.copyWith(
                        color: themeState.textPrimary,
                      ),
                    ),
                    if (note != null)
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              for (final action in actions) FriendActionButton(action: action),
            ],
          ),
        ),
      ),
    );
  }
}
