import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/enums/notification_level.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import 'dm_conversation_tile.dart';
import 'dm_list_header.dart';

/// The conversation list down the left of the server-DM surface.
///
/// Central DMs no longer come through here: Home is a tier of its own and its
/// list lives in the sidebar column (see `CentralConversationList`). Server DMs
/// are scoped to the server whose channels the sidebar is already showing, so
/// they open as a pane inside the content panel instead.
///
/// It **pages** (`011_directory.sql`), like central's does. The list is bounded by
/// how many people you have talked to rather than by how much was said, so it
/// was the slowest of the app's reads to become a problem — and the only one
/// that never truncated, since it comes back as one JSONB value rather than as
/// rows. What it did instead was decrypt a preview for every conversation on
/// the server to draw the dozen that fit on screen.
class DmListPanel extends StatelessWidget {
  final String title;

  /// Sits under [title] in the header — a handle, a server name.
  final String? subtitle;

  final List<DmConversation> conversations;
  final String? openPeerId;
  final void Function(DmConversation) onOpen;

  /// Whether another page follows, and how to ask for it. Both null together:
  /// a caller with no more to give offers no footer and no scroll listener.
  final bool hasMore;
  final Future<void> Function()? onLoadMore;

  /// The member search that starts a new conversation, under the header.
  /// Null until a server is selected — there is nobody to search.
  final Widget? search;

  /// Shown in place of the list when there are no conversations.
  final Widget? emptyState;

  /// Unread messages from a peer, for the per-row badge. Null means the caller
  /// has no unread information — every row then shows none.
  final int Function(String peerId)? unreadFor;

  /// How much a peer's conversation may interrupt, for the row's right-click
  /// menu. Null means the caller has nowhere to store an answer, and no menu
  /// is offered.
  final NotificationLevel Function(String peerId)? levelFor;

  /// Called when a row's menu picks a level.
  final void Function(String peerId, NotificationLevel level)? onLevelChanged;

  const DmListPanel({
    super.key,
    required this.title,
    required this.conversations,
    required this.onOpen,
    this.subtitle,
    this.openPeerId,
    this.hasMore = false,
    this.onLoadMore,
    this.search,
    this.emptyState,
    this.unreadFor,
    this.levelFor,
    this.onLevelChanged,
  });

  /// How close to the bottom counts as "nearly there" — about three tiles.
  static const double _loadMoreSlack = 180;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DmListHeader(title: title, subtitle: subtitle),
            if (search != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: search!,
              ),
            Expanded(child: _buildList(themeState)),
          ],
        );
      },
    );
  }

  Widget _buildList(ThemeState themeState) {
    if (conversations.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: emptyState ?? const SizedBox.shrink(),
      );
    }

    // The label and the note ride in the list rather than around it, so they
    // scroll with the rows they belong to — the same way channel sections do.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final loadMore = onLoadMore;
        if (hasMore &&
            loadMore != null &&
            notification.metrics.extentAfter < _loadMoreSlack) {
          unawaited(loadMore());
        }
        // Never swallowed — the scrollbar is still listening.
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: conversations.length + (hasMore ? 2 : 1),
        itemBuilder: (context, index) {
          if (index == 0) return const SectionHeader(label: 'Conversations');
          if (index > conversations.length) return _buildFooter();
          return _tile(themeState, conversations[index - 1]);
        },
      ),
    );
  }

  /// The spinner at the end of a page, which is also what says the list has not
  /// simply stopped.
  Widget _buildFooter() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _tile(ThemeState themeState, DmConversation conversation) {
    final onLevelChanged = this.onLevelChanged;
    return DmConversationTile(
      conversation: conversation,
      isSelected: conversation.peerId == openPeerId,

      unreadCount: unreadFor?.call(conversation.peerId) ?? 0,
      level: levelFor?.call(conversation.peerId) ?? NotificationLevel.dmDefault,
      onLevelChanged: onLevelChanged == null
          ? null
          : (level) => onLevelChanged(conversation.peerId, level),
      onTap: () => onOpen(conversation),
    );
  }
}
