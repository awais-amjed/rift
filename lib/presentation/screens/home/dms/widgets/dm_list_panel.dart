import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../channels/channel_list/widgets/section_header.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/chat_header_button.dart';
import 'dm_conversation_tile.dart';

/// The conversation list down the left of a DM surface.
///
/// Both tiers use this — central DMs and server DMs differ in *which*
/// conversations they hold and what sits above them, not in how a list of
/// conversations looks. [slot] is where a tier puts what makes it itself: the
/// central account's identity and handle search, or nothing at all.
class DmListPanel extends StatelessWidget {
  final String title;

  /// Sits under [title] in the header — a handle, a server name.
  final String? subtitle;

  /// Tier-specific content above the list (identity block, search field).
  final Widget? slot;

  final List<DmConversation> conversations;
  final String? openPeerId;
  final void Function(DmConversation) onOpen;

  /// Starts a new conversation. Null disables the "+" — the central tier
  /// can't start one until an account is signed in and a handle claimed.
  final VoidCallback? onNew;

  /// Shown in place of the list when there are no conversations.
  final Widget? emptyState;

  /// A standing note under the conversations — the central tier explains what
  /// it is for there. Scrolls with the list rather than pinning to the panel,
  /// so it never competes with the dock below it.
  final Widget? footer;

  const DmListPanel({
    super.key,
    required this.title,
    required this.conversations,
    required this.onOpen,
    this.subtitle,
    this.slot,
    this.openPeerId,
    this.onNew,
    this.emptyState,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(themeState),
            if (slot != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: slot!,
              ),
            Expanded(child: _buildList(themeState)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ThemeState themeState) {
    return Container(
      height: ChatHeader.height,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        children: [
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
          if (onNew != null)
            ChatHeaderButton(
              icon: Icons.add_rounded,
              tooltip: 'New conversation',
              isPrimary: true,
              onTap: onNew!,
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
      itemCount: conversations.length + (footer == null ? 1 : 2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SectionHeader(label: 'Conversations');
        }
        if (index > conversations.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 2, 12),
            child: footer!,
          );
        }
        final conversation = conversations[index - 1];
        return DmConversationTile(
          conversation: conversation,
          isSelected: conversation.peerId == openPeerId,
          themeState: themeState,
          onTap: () => onOpen(conversation),
        );
      },
    );
  }
}
