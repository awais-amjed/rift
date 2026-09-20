import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/enums/friendship_state.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../theme/app_text.dart';
import '../mobile/widgets/mini_call_bar.dart';
import 'widgets/dm_chat_header.dart';
import 'widgets/friends/friend_request_bar.dart';
import 'widgets/friends/not_friends_note.dart';
import 'widgets/friends/pending_request_note.dart';
import 'widgets/quota_meter.dart';

/// The open central-DM conversation. Central is the discovery funnel:
/// the composer footer shows the daily quota, and sends stop at zero.
class CentralDmChatView extends StatefulWidget {
  const CentralDmChatView({super.key});

  @override
  State<CentralDmChatView> createState() => _CentralDmChatViewState();
}

class _CentralDmChatViewState extends State<CentralDmChatView>
    with
        ChatScrollLoadMore<CentralDmChatView>,
        ChatReplyDraft<CentralDmChatView> {
  @override
  void loadMoreHistory() => context.read<CentralDmCubit>().loadMoreHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final quotaEmpty = state.remaining != null && state.remaining! <= 0;
    final peerId = state.openPeerId;
    final handle = state.openPeerHandle ?? '';
    final friendship = peerId == null
        ? FriendshipState.none
        : state.stateFor(peerId);

    return Column(
      children: [
        DmChatHeader(
          tierIcon: Icons.public,
          tierLabel: 'Central',
          title: '@${state.openPeerHandle ?? ''}',
          peerId: state.openPeerId,
          onClose: () => context.read<CentralDmCubit>().closeConversation(),
        ),
        Expanded(child: _buildBody(state, themeState)),
        // A phone's way back into a call, above the composer's slot.
        const MiniCallBar(),
        // There is a composer here for exactly one of the five states, and
        // every other branch is a sentence saying what would have to change.
        // None of them is a disabled field: a greyed composer with a hint in
        // it reads as something that has broken, and people retype into it.
        if (state.chatStatus == DmChatStatus.ready && peerId != null)
          switch (friendship) {
            FriendshipState.friends => ChatComposer(
              hintText: quotaEmpty
                  ? 'Daily limit reached — continue on a shared server'
                  : 'Message @$handle',
              enabled: !quotaEmpty,
              maxAttachmentBytes: ServerLimits.centralMaxAttachmentBytes,
              footer: const QuotaMeter(),
              onSend: (text, attachments, preview) =>
                  _send(context, text, attachments, preview),
              replyingTo: replyingTo,
              onCancelReply: cancelReply,
            ),
            FriendshipState.incoming => FriendRequestBar(
              peerId: peerId,
              peerHandle: handle,
            ),
            FriendshipState.outgoing => PendingRequestNote(
              peerId: peerId,
              peerHandle: handle,
            ),
            // A conversation you can read and not add to: somebody unfriended,
            // or blocked and not yet cleared off this screen. Both are old
            // history with a closed door on it, and the note offers the way
            // back through.
            FriendshipState.none || FriendshipState.blocked => NotFriendsNote(
              peerId: peerId,
              peerHandle: handle,
              isBlocked: friendship == FriendshipState.blocked,
            ),
          },
      ],
    );
  }

  /// Send, clearing the reply bar with the same press that clears the field.
  ///
  /// No ping toggle here and none offered: a DM wakes the one person in it
  /// whatever the message says, so a control for whether it does would be a
  /// switch wired to nothing.
  void _send(
    BuildContext context,
    String text,
    List<PendingAttachment> attachments,
    PendingLinkPreview? preview,
  ) {
    final answering = replyToId;
    cancelReply();
    context.read<CentralDmCubit>().sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: answering,
    );
  }

  Widget _buildBody(CentralDmState state, ThemeState themeState) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        syncReplyDraft(state.openPeerId, state.messages);
        return ChatMessageList(
          key: ValueKey(state.openPeerId),
          messages: state.messages,
          // The default invites the first message. There is nowhere to type it
          // unless the two of you are friends, and an invitation printed above
          // the note explaining that is the screen arguing with itself.
          emptyMessage: state.canSendToOpen
              ? 'No messages yet — say hi!'
              : 'Nothing here yet.',
          controller: scrollController,
          attachmentLoader: context.read<CentralDmCubit>().loadAttachment,
          // No onToggleReaction: central DMs are the first-contact tier and are
          // kept deliberately thin — reactions live on servers.
          onReply: startReply,
          onEdit: context.read<CentralDmCubit>().editMessage,
          onDelete: context.read<CentralDmCubit>().deleteMessage,
          onRetry: context.read<CentralDmCubit>().retrySend,
          // The only two people who will ever read this. Naming anyone else
          // would light up a mention that cannot reach them.
          mentionable: {
            for (final handle in [state.myHandle, state.openPeerHandle])
              if (handle != null) handle.toLowerCase(),
          },
        );
      case DmChatStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DmChatStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              state.error ?? 'Could not open this conversation.',
              textAlign: TextAlign.center,
              style: AppText.rowQuiet.copyWith(color: themeState.textTertiary),
            ),
          ),
        );
      case DmChatStatus.closed:
        return const SizedBox.shrink();
    }
  }
}
