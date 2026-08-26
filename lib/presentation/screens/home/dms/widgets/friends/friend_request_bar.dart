import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/friend.dart';
import '../../../../../../data/enums/friendship_state.dart';
import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../theme/app_text.dart';
import 'friend_actions.dart';

/// Where the composer would be, for somebody who has asked to be your friend.
///
/// Whatever is above it is old — a conversation you two had before, if there
/// was one — because a request arrives empty and there is nothing new to read.
/// Putting the three answers where the field goes is what makes this read as a
/// choice rather than as a broken composer.
///
/// The copy's job is to say that the silence is enforced. Somebody who has
/// asked to reach you cannot send anything while you decide, and a person
/// deciding whether to accept a stranger deserves to know that declining is
/// not a door they are holding shut by hand.
class FriendRequestBar extends StatelessWidget {
  final String peerId;
  final String peerHandle;

  const FriendRequestBar({
    super.key,
    required this.peerId,
    required this.peerHandle,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final cubit = context.read<CentralDmCubit>();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '@$peerHandle wants to be friends',
            style: AppText.row.copyWith(color: themeState.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            'They cannot send you anything until you accept. Accepting lets '
            'you both message freely; declining just removes the request.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              AppButton(
                label: 'Accept',
                onPressed: () => cubit.acceptRequest(peerId),
              ),
              AppButton(
                label: 'Decline',
                variant: AppButtonVariant.secondary,
                onPressed: () => cubit.declineRequest(peerId),
              ),
              const Spacer(),
              AppButton(
                label: 'Block',
                variant: AppButtonVariant.danger,
                // The same confirmation the friends page asks, from the same
                // place — a block is a block wherever it is pressed.
                onPressed: () => FriendActions.confirmBlock(
                  context,
                  Friend(
                    id: peerId,
                    handle: peerHandle,
                    state: FriendshipState.incoming,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
