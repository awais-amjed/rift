import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/enums/friendship_state.dart';
import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../common/confirm_dialog.dart';
import 'friend_row_action.dart';

/// What a row offers, and what it says, for each place you can stand with
/// somebody.
///
/// One switch over [FriendshipState] in the whole feature. Every list — the
/// friends page, a conversation's right-click menu, the bar under a request —
/// asks this rather than deciding for itself, because a person in two lists
/// that disagree about what can be done to them is the bug this exists to
/// prevent.
///
/// The two that end a standing relationship ask first. The two that answer a
/// request do not: declining is the ordinary counterpart of accepting, and an
/// inbox that demands confirmation for the common case is an inbox people stop
/// opening. Its tooltip says what it does instead.
class FriendActions {
  const FriendActions._();

  /// The quiet second line under the handle, or null where the handle is the
  /// whole story.
  static String? noteFor(FriendshipState state) => switch (state) {
    FriendshipState.incoming => 'Wants to be friends',
    FriendshipState.outgoing => 'Waiting for them to accept',
    FriendshipState.blocked => 'Blocked — they cannot find or reach you',
    _ => null,
  };

  static List<FriendRowAction> forFriend(BuildContext context, Friend friend) {
    final cubit = context.read<CentralDmCubit>();
    final handle = '@${friend.handle}';

    switch (friend.state) {
      case FriendshipState.incoming:
        return [
          FriendRowAction(
            icon: Icons.check_rounded,
            tooltip: 'Accept',
            onTap: () => cubit.acceptRequest(friend.id),
          ),
          FriendRowAction(
            icon: Icons.close_rounded,
            tooltip: 'Decline',
            isDangerous: true,
            onTap: () => cubit.declineRequest(friend.id),
          ),
          FriendRowAction(
            icon: Icons.block_rounded,
            tooltip: 'Block',
            isDangerous: true,
            onTap: () => confirmBlock(context, friend),
          ),
        ];

      case FriendshipState.outgoing:
        return [
          FriendRowAction(
            icon: Icons.undo_rounded,
            tooltip: 'Withdraw request',
            onTap: () => cubit.removeFriend(friend.id),
          ),
        ];

      case FriendshipState.friends:
        return [
          FriendRowAction(
            icon: Icons.person_remove_outlined,
            tooltip: 'Remove friend',
            isDangerous: true,
            onTap: () => _confirmThen(
              context: context,
              title: 'Remove $handle?',
              message:
                  'You will both need a new request to talk again. The '
                  'conversation itself stays where it is.',
              confirmLabel: 'Remove friend',
              icon: Icons.person_remove_outlined,
              action: () => cubit.removeFriend(friend.id),
            ),
          ),
          FriendRowAction(
            icon: Icons.block_rounded,
            tooltip: 'Block',
            isDangerous: true,
            onTap: () => confirmBlock(context, friend),
          ),
        ];

      case FriendshipState.blocked:
        return [
          FriendRowAction(
            icon: Icons.lock_open_rounded,
            tooltip: 'Unblock',
            onTap: () => cubit.unblockPeer(friend.id),
          ),
        ];

      // Somebody you used to talk to. Block is here as well as on a request,
      // because this is the state an ex-friend sits in and the thing you may
      // want is for them not to be able to ask again.
      case FriendshipState.none:
        return [
          FriendRowAction(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: 'Add friend',
            onTap: () => cubit.addFriend(friend.id),
          ),
          FriendRowAction(
            icon: Icons.block_rounded,
            tooltip: 'Block',
            isDangerous: true,
            onTap: () => confirmBlock(context, friend),
          ),
        ];
    }
  }

  /// Block, after asking. Public because the request bar in the chat offers
  /// the same button, and a block must ask the same question wherever it is
  /// pressed.
  static Future<void> confirmBlock(BuildContext context, Friend friend) =>
      _confirmThen(
        context: context,
        title: 'Block @${friend.handle}?',
        message:
            'They will not be able to message you or find your handle, and any '
            'friendship between you ends. They are not told.',
        confirmLabel: 'Block',
        icon: Icons.block_rounded,
        action: () => context.read<CentralDmCubit>().blockPeer(friend.id),
      );

  static Future<void> _confirmThen({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required Future<bool> Function() action,
  }) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      isDestructive: true,
    );
    if (confirmed) await action();
  }
}
