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
import 'widgets/profile_handle_row.dart';
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
class CentralProfileDialog extends StatefulWidget {
  /// The person as the opening surface knew them.
  final Friend friend;

  const CentralProfileDialog({super.key, required this.friend});

  @override
  State<CentralProfileDialog> createState() => _CentralProfileDialogState();
}

class _CentralProfileDialogState extends State<CentralProfileDialog> {
  late FriendshipState _standing = widget.friend.state;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  /// Ask the server where we stand, rather than reading it off the graph.
  ///
  /// The buckets cannot answer this, and the way they cannot is worth
  /// spelling out: every friend action reloads the *counts* and drops every
  /// loaded page with them, so a request accepted from here leaves the only
  /// page that mentioned this person gone. Reading it back off the graph
  /// showed the request still waiting, under three buttons that no longer
  /// applied. One row, asked by id, is the authoritative answer.
  Future<void> _ask() async {
    final next = await context.read<CentralDmCubit>().friendshipState(
      widget.friend.id,
    );
    if (!mounted || next == _standing) return;
    setState(() => _standing = next);
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final current = Friend(
      id: friend.id,
      handle: friend.handle,
      chatPublicKey: friend.chatPublicKey,
      signingPublicKey: friend.signingPublicKey,
      since: friend.since,
      state: _standing,
    );

    return BlocListener<CentralDmCubit, CentralDmState>(
      // Every successful action ends in a counts reload, whichever it was, so
      // this catches all six without the dialog having to know which button
      // leads to which standing — the switch in [FriendActions] is the one
      // place that is allowed to know.
      listenWhen: (before, after) =>
          before.friends.counts != after.friends.counts,
      listener: (_, _) => _ask(),
      child: AppModal(
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
                  ..._facts(current),
                  // Not while they are blocked. The line below says they
                  // cannot reach you; handing over a copyable address in the
                  // same breath contradicts it.
                  if (_standing != FriendshipState.blocked)
                    ProfileHandleRow(handle: current.handle),
                ],
              ),
            ),
            // Only for a block, and not because the others have no note — the
            // friends row has one for each. It is that "Wants to be friends"
            // and "Waiting for them" say their own consequence, and a block
            // does not: what it actually does is make you unfindable, which
            // is the whole reason to choose it over removing somebody.
            if (_standing == FriendshipState.blocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'They cannot find or reach you.',
                  style: AppText.secondary.copyWith(
                    color: context.theme.textTertiary,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            if (_standing.canSend)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AppButton(
                  label: 'Message',
                  expanded: true,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  onPressed: current.chatPublicKey == null
                      ? null
                      : () {
                          // Open first, close second: the helper reads two
                          // cubits off this context, and popping deactivates
                          // it before they can be read.
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
      ),
    );
  }

  List<Widget> _facts(Friend current) {
    // The date came from the row that named the *old* standing, and the
    // server's answer carries no new one. Drawing it against a standing it
    // does not describe would be the worst of the three — "Friends since"
    // over the date they asked. So it goes, until the surface behind reopens
    // the profile with a fresh row.
    final since = _standing == widget.friend.state ? current.since : null;
    return [
      ProfileFact(label: 'Standing', value: _standingLabel(_standing)),
      if (since != null)
        ProfileFact(
          label: _sinceLabel(_standing),
          value: DateFormat('d MMMM y').format(since.toLocal()),
        ),
      ProfileFact(
        label: 'Encrypted chat',
        value: current.chatPublicKey == null ? 'Not set up' : 'Ready',
        quiet: current.chatPublicKey == null,
      ),
    ];
  }

  static String _standingLabel(FriendshipState state) => switch (state) {
    FriendshipState.friends => 'Friends',
    FriendshipState.incoming => 'Wants to be friends',
    FriendshipState.outgoing => 'Waiting for them',
    FriendshipState.blocked => 'Blocked',
    FriendshipState.none => 'Not friends',
  };

  /// What the date on the row means, which is not the same thing in every
  /// state — the graph returns one `since` and it is the moment the current
  /// standing began.
  static String _sinceLabel(FriendshipState state) => switch (state) {
    FriendshipState.friends => 'Friends since',
    FriendshipState.incoming => 'Asked you',
    FriendshipState.outgoing => 'You asked',
    FriendshipState.blocked => 'Blocked on',
    FriendshipState.none => 'Last changed',
  };
}
