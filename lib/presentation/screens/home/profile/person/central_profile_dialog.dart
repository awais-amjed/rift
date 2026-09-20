import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../../data/classes/friend.dart';
import '../../../../../data/enums/friendship_state.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../dms/open_central_conversation.dart';
import '../../dms/widgets/friends/friend_actions.dart';
import 'widgets/profile_action_button.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_fact.dart';
import 'widgets/profile_section.dart';

/// Who somebody is on the **central tier**: a handle, where you stand with
/// them, and the one or two things that can change it.
///
/// Much thinner than a server profile, and that is the tier being honest
/// rather than the screen being unfinished. Central holds a handle and two
/// public keys and nothing else — no roles, no presence, no tenure it would
/// be safe to show a stranger. What it does hold is a *relationship*, which a
/// server has no equivalent of, so that is what this profile is mostly about.
///
/// No presence dot for the same reason: nobody is watching, and a grey dot
/// would claim they are offline rather than admit that.
class CentralProfileDialog extends StatelessWidget {
  /// The person as the opening surface knew them. Their standing is re-read
  /// from the cubit on every build, because acting on it from here is most of
  /// what this dialog is for — the button has to become "Remove friend" the
  /// moment the request is accepted.
  final Friend friend;

  const CentralProfileDialog({super.key, required this.friend});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CentralDmCubit>().state;
    final current = Friend(
      id: friend.id,
      handle: friend.handle,
      chatPublicKey: friend.chatPublicKey,
      signingPublicKey: friend.signingPublicKey,
      since: friend.since,
      // The loaded friends tabs first — an action taken here refetches them,
      // so they are the half that just moved. Then the conversation row,
      // which is authoritative but only refreshes with the list.
      state:
          state.friends.stateOf(friend.id) ??
          _conversationState(state) ??
          friend.state,
    );

    final note = FriendActions.noteFor(current.state);

    return AppModal(
      title: '@${current.handle}',
      subtitle: 'Central account',
      titleIcon: ProfileAvatar(name: current.handle, seed: current.id),
      maxWidth: 400,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileSection(
            label: 'About',
            spaced: false,
            child: Column(
              children: [
                ProfileFact(label: 'Standing', value: _standing(current.state)),
                if (current.since != null)
                  ProfileFact(
                    label: _sinceLabel(current.state),
                    value: DateFormat(
                      'd MMMM y',
                    ).format(current.since!.toLocal()),
                  ),
                ProfileFact(
                  label: 'Encrypted chat',
                  value: current.chatPublicKey == null ? 'Not set up' : 'Ready',
                  quiet: current.chatPublicKey == null,
                ),
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                style: AppText.secondary.copyWith(
                  color: context.theme.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: 18),
          if (current.state.canSend)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppButton(
                label: 'Message',
                expanded: true,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                onPressed: current.chatPublicKey == null
                    ? null
                    : () {
                        // Open first, close second: `openCentralConversation`
                        // reads two cubits off this context, and popping
                        // deactivates it before they can be read.
                        openCentralConversation(
                          context,
                          current.toConversation(),
                        );
                        Navigator.of(context).pop();
                      },
              ),
            ),
          // The same switch the friends list asks — a person who can be
          // unfriended in one place and not the other is the bug
          // [FriendActions] exists to prevent.
          for (final action in FriendActions.forFriend(context, current))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ProfileActionButton(action: action),
            ),
        ],
      ),
    );
  }

  FriendshipState? _conversationState(CentralDmState state) {
    for (final conversation in state.conversations) {
      if (conversation.peerId == friend.id) return conversation.state;
    }
    return null;
  }

  static String _standing(FriendshipState state) => switch (state) {
    FriendshipState.friends => 'Friends',
    FriendshipState.incoming => 'Request received',
    FriendshipState.outgoing => 'Request sent',
    FriendshipState.blocked => 'Blocked',
    FriendshipState.none => 'Not friends',
  };

  /// What the date on the row means, which is not the same thing in every
  /// state — the server returns one `since` and it is the moment the current
  /// standing began.
  static String _sinceLabel(FriendshipState state) => switch (state) {
    FriendshipState.friends => 'Friends since',
    FriendshipState.incoming => 'Asked you',
    FriendshipState.outgoing => 'You asked',
    FriendshipState.blocked => 'Blocked on',
    FriendshipState.none => 'Last changed',
  };
}
