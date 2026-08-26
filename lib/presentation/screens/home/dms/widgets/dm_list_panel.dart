import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/enums/notification_level.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/header_pane_buttons.dart';
import 'dm_conversation_tile.dart';

/// The conversation list down the left of the server-DM surface.
///
/// Central DMs no longer come through here: Home is a tier of its own and its
/// list lives in the sidebar column (see `CentralDmListPanel`). Server DMs are
/// scoped to the server whose channels the sidebar is already showing, so they
/// open as a pane inside the content panel instead.
class DmListPanel extends StatelessWidget {
  final String title;

  /// Sits under [title] in the header — a handle, a server name.
  final String? subtitle;

  final List<DmConversation> conversations;
  final String? openPeerId;
  final void Function(DmConversation) onOpen;

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
    this.search,
    this.emptyState,
    this.unreadFor,
    this.levelFor,
    this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, themeState),
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

  /// On a phone this list is the whole surface, so its header is the only bar
  /// on screen and has to carry the way back to the drawer. [HeaderSidebarButton]
  /// renders nothing where the sidebar is docked, so the wide layout is
  /// unchanged and keeps its tighter lead-in.
  Widget _buildHeader(BuildContext context, ThemeState themeState) {
    final hasMenu = context.layoutMode.sidebarIsOverlay;

    return Container(
      height: ChatHeader.height,
      padding: EdgeInsets.fromLTRB(hasMenu ? 6 : 14, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      // No "+": the search field below is the way to start a conversation,
      // and a button whose only job is to point at a field already on screen
      // is one control too many.
      child: Row(
        spacing: hasMenu ? 8 : 0,
        children: [
          const HeaderSidebarButton(),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(
                      color: themeState.textQuaternary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: conversations.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SectionHeader(label: 'Conversations');
        }
        final conversation = conversations[index - 1];
        final onLevelChanged = this.onLevelChanged;
        return DmConversationTile(
          conversation: conversation,
          isSelected: conversation.peerId == openPeerId,
          themeState: themeState,
          unreadCount: unreadFor?.call(conversation.peerId) ?? 0,
          level:
              levelFor?.call(conversation.peerId) ??
              NotificationLevel.dmDefault,
          onLevelChanged: onLevelChanged == null
              ? null
              : (level) => onLevelChanged(conversation.peerId, level),
          onTap: () => onOpen(conversation),
        );
      },
    );
  }
}
