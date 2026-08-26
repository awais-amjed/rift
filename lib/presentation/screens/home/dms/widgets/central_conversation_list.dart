import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/classes/friend.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/hint_card.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import '../open_central_conversation.dart';
import 'dm_conversation_tile.dart';
import 'friends/friend_actions.dart';
import 'friends/friend_menu_item.dart';

/// The central column's conversations.
///
/// One list, and that is the point of the gate rather than an omission. There
/// used to be a Requests section above this one, because a stranger's first
/// message *was* their request and it had to land somewhere separate. Nothing
/// arrives from a stranger any more — a request carries no message — so the
/// only people here are people you agreed to hear from, and requests live on
/// the friends page where they can be answered.
///
/// A blocked peer is left out: their old messages are still rows on the server
/// (blocking takes away reach, not history), and [FriendDirectory.visible] is
/// what keeps them out of the list.
class CentralConversationList extends StatelessWidget {
  const CentralConversationList({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final conversations = state.graph.visible(state.conversations);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        const SectionHeader(label: 'Conversations'),
        for (final conversation in conversations)
          _tile(context, state, themeState, conversation),
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 14, 2, 12),
          child: HintCard(
            text:
                'Central DMs are for finding each other. For longer chats, '
                'move to a server you share.',
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    CentralDmState state,
    ThemeState themeState,
    DmConversation conversation,
  ) {
    return DmConversationTile(
      conversation: conversation,
      isSelected: conversation.peerId == state.openPeerId,
      themeState: themeState,
      unreadCount: state.unreadByPeer[conversation.peerId] ?? 0,
      level: state.levelFor(conversation.peerId),
      menuItems: [
        for (final action in FriendActions.forFriend(
          context,
          Friend.fromConversation(
            conversation,
            state.stateFor(conversation.peerId),
          ),
        ))
          FriendMenuItem(action: action),
      ],
      onLevelChanged: (level) => context
          .read<CentralDmCubit>()
          .setNotificationLevel(conversation.peerId, level),
      onTap: () => openCentralConversation(context, conversation),
    );
  }
}
