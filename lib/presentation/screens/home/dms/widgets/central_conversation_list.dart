import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/classes/friend.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/list_loading_footer.dart';
import '../../../../theme/theme_context.dart';
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
/// A blocked peer is left out by the *query* (central migration 014). Their
/// old messages are still rows on the server — blocking takes away reach, not
/// history — so something has to leave them out, and it has to be on the same
/// side of the page boundary as the paging: a filter applied after a page
/// arrives shortens it, while `has_more` and the cursor were computed for the
/// rows the filter then dropped.
///
/// It **pages** (central migration 013). The list used to be derived on the
/// client from the last thousand envelopes, which meant an old conversation
/// silently stopped existing rather than sitting further down — and there was
/// nothing to scroll to, because there was no cursor into a list nobody was
/// querying.
///
/// And built lazily, for the same reason it pages. Every tile assembles its
/// own context menu through `FriendActions.forFriend`, so drawing them all
/// eagerly did that work for conversations nobody had scrolled to — on a list
/// whose whole point is that it has no upper bound.
class CentralConversationList extends StatelessWidget {
  const CentralConversationList({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<CentralDmCubit>().state;
    final conversations = state.conversations;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (state.hasMoreConversations &&
            notification.metrics.extentAfter < _loadMoreSlack) {
          unawaited(context.read<CentralDmCubit>().loadMoreConversations());
        }
        // Never swallowed — the scrollbar is still listening.
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // One header, the conversations, a spinner while there are more, and
        // the note at the end.
        itemCount: conversations.length + (state.hasMoreConversations ? 3 : 2),
        itemBuilder: (context, index) {
          if (index == 0) return const SectionHeader(label: 'Conversations');

          final at = index - 1;
          if (at < conversations.length) {
            return _tile(context, state, themeState, conversations[at]);
          }
          if (state.hasMoreConversations && at == conversations.length) {
            return const ListLoadingFooter();
          }
          return const Padding(
            padding: EdgeInsets.fromLTRB(2, 14, 2, 12),
            child: HintCard(
              text:
                  'Central DMs are for finding each other. For longer chats, '
                  'move to a server you share.',
            ),
          );
        },
      ),
    );
  }

  /// How close to the bottom counts as "nearly there" — about three tiles.
  static const double _loadMoreSlack = 180;

  Widget _tile(
    BuildContext context,
    CentralDmState state,
    ThemeState themeState,
    DmConversation conversation,
  ) {
    return DmConversationTile(
      conversation: conversation,
      isSelected: conversation.peerId == state.openPeerId,

      unreadCount: state.unreadByPeer[conversation.peerId] ?? 0,
      level: state.levelFor(conversation.peerId),
      menuItems: [
        for (final action in FriendActions.forFriend(
          context,
          // The row's own state, off the row. Nothing here consults a graph.
          Friend.fromConversation(
            conversation,
            conversation.state ?? state.stateFor(conversation.peerId),
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
