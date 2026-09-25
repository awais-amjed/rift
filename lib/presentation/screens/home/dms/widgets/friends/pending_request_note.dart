import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Where the composer would be, for a request of your own that is still
/// unanswered.
///
/// The field is not merely disabled: it is gone, and this says why. A greyed
/// composer with a hint in it reads as something that has broken, and people
/// retype into it. There is no allowance to spend — a request carries no
/// message — so there is nothing here to type into until they answer.
///
/// Withdrawing is cheap and undoable, and that is fine: it takes nothing with
/// it and re-asking delivers nothing. It used to be worth doing over and over,
/// because each round trip bought the sender another message; that is the hole
/// this version of the gate closed.
class PendingRequestNote extends StatelessWidget {
  final String peerId;
  final String peerHandle;

  const PendingRequestNote({
    super.key,
    required this.peerId,
    required this.peerHandle,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 12, 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: K.iconRow,
            color: themeState.textQuaternary,
          ),
          Expanded(
            child: Text(
              'Waiting for @$peerHandle to accept your friend request. You '
              'can message them once they do.',
              style: AppText.secondary.copyWith(color: themeState.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.read<CentralDmCubit>().removeFriend(peerId),
            child: Text(
              'Withdraw',
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
