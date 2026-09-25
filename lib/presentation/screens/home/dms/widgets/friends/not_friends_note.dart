import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Where the composer would be, for a conversation with somebody you are not
/// friends with.
///
/// Reached two ways, and both are histories rather than beginnings: you
/// unfriended them, or you blocked them and this screen has not caught up yet.
/// Neither deletes anything — a conversation belongs to two people and neither
/// gets to erase it from the other — so what is left is readable, unaddable
/// to, and honest about which.
///
/// The action is the way back through the same door: ask again, or unblock.
/// Both leave you a stranger who has to be accepted, which is the only thing
/// that opens a composer on this tier.
class NotFriendsNote extends StatelessWidget {
  final String peerId;
  final String peerHandle;

  /// Whether the reason is a block of your own rather than an unfriending.
  /// It changes the sentence and the button, not the shape.
  final bool isBlocked;

  const NotFriendsNote({
    super.key,
    required this.peerId,
    required this.peerHandle,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final cubit = context.read<CentralDmCubit>();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 12, 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(
            isBlocked ? Icons.block_rounded : Icons.person_off_outlined,
            size: K.iconRow,
            color: themeState.textQuaternary,
          ),
          Expanded(
            child: Text(
              isBlocked
                  ? 'You have @$peerHandle blocked. They cannot find or reach '
                        'you.'
                  : 'You and @$peerHandle are not friends. You can read this '
                        'conversation, but not add to it.',
              style: AppText.secondary.copyWith(color: themeState.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () =>
                isBlocked ? cubit.unblockPeer(peerId) : cubit.addFriend(peerId),
            child: Text(
              isBlocked ? 'Unblock' : 'Add friend',
              style: AppText.secondary.copyWith(
                color: themeState.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
