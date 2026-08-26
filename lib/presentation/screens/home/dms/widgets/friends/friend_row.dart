import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/squircle_avatar.dart';
import '../../../../../theme/app_text.dart';
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

  const FriendRow({
    super.key,
    required this.friend,
    this.note,
    this.actions = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final radius = BorderRadius.circular(K.radiusButton);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            spacing: 11,
            children: [
              SquircleAvatar(name: friend.handle, seed: friend.id, size: 34),
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
                        fontSize: 13,
                        color: themeState.textPrimary,
                      ),
                    ),
                    if (note != null)
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(
                          fontSize: 11.5,
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
