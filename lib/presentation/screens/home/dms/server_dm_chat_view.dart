import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/forward/show_forward_dialog.dart';
import '../../../common/chat/typing_indicator.dart';
import '../../../common/loading_dots.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../mobile/widgets/mini_call_bar.dart';
import '../profile/person/show_person_profile.dart';
import 'widgets/dm_chat_header.dart';

/// Over the widget budget and one job: the open server DM.
///
/// The open server-DM conversation: header + history + composer, on the
/// shared chat kit.
class ServerDmChatView extends StatefulWidget {
  const ServerDmChatView({super.key});

  @override
  State<ServerDmChatView> createState() => _ServerDmChatViewState();
}

class _ServerDmChatViewState extends State<ServerDmChatView>
    with
        ChatScrollLoadMore<ServerDmChatView>,
        ChatReplyDraft<ServerDmChatView> {
  @override
  void loadMoreHistory() => context.read<DmCubit>().loadMoreHistory();

  @override
  void loadNewerHistory() => context.read<DmCubit>().loadNewerHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<DmCubit>().state;

    return Column(
      children: [
        DmChatHeader(
          tierIcon: Icons.dns_outlined,
          tierLabel: 'Server',
          title: state.openPeerName ?? '',
          peerId: state.openPeerId,
          onOpenProfile: state.openPeerId == null
              ? null
              : () => unawaited(
                  showMemberProfile(
                    context,
                    userId: state.openPeerId!,
                    name: state.openPeerName ?? '',
                  ),
                ),
          onClose: () => context.read<DmCubit>().closeConversation(),
        ),
        Expanded(child: _buildBody(state, themeState)),
        if (state.chatStatus != DmChatStatus.ready) const MiniCallBar(),
        if (state.chatStatus == DmChatStatus.ready) ...[
          TypingIndicator(
            names: state.typingPeerName != null
                ? [state.typingPeerName!]
                : const [],
          ),
          const MiniCallBar(),
          ChatComposer(
            hintText: 'Message ${state.openPeerName ?? ''}',
            maxAttachmentBytes: _maxAttachmentBytes(),
            remainingStorageBytes: _remainingStorage(),
            onSend: (text, attachments, preview) =>
                _send(context, text, attachments, preview),
            replyingTo: replyingTo,
            onCancelReply: cancelReply,
            onTyping: () => context.read<DmCubit>().notifyTyping(),
          ),
        ],
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
    context.read<DmCubit>().sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: answering,
    );
  }

  /// The operator's per-file attachment cap for this server.
  int _maxAttachmentBytes() =>
      (context.read<ServerCubit>().state.selectedServer?.limits ??
              ServerLimits.defaults)
          .maxAttachmentBytes;

  /// What the whole server has room for (migration 029), or null when it has
  /// no storage limit. Server DMs live in the same bucket as the channels,
  /// so they answer to the same ceiling.
  int? _remainingStorage() {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return null;
    return server.limits.remainingStorage(server.storageUsed);
  }

  /// The two people in this conversation, by username.
  ///
  /// Not the whole server roster, even though it is right there: a DM reaches
  /// two people, so lighting up a third member's name would promise a ping
  /// that nobody will ever receive.
  Set<String> _mentionable(DmState state) {
    final me = context.read<ServerCubit>().state.selectedServer?.user?.username;
    final peer = state.openPeerId == null
        ? null
        : context
              .read<ServerMembersCubit>()
              .state
              .byId[state.openPeerId]
              ?.username;
    return {
      for (final name in [me, peer])
        if (name != null) name.toLowerCase(),
    };
  }

  Widget _buildBody(DmState state, ThemeState themeState) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        syncReplyDraft(state.openPeerId, state.messages);
        return ChatMessageList(
          key: ValueKey(state.openPeerId),
          messages: state.messages,
          controller: scrollController,
          attachmentLoader: context.read<DmCubit>().loadAttachment,
          onToggleReaction: context.read<DmCubit>().toggleReaction,
          onLookUpOriginal: context.read<DmCubit>().fetchQuoted,
          onShowAround: context.read<DmCubit>().showAround,
          viewingHistory: state.hasNewerHistory,
          onReturnToPresent: context.read<DmCubit>().returnToPresent,
          onOpenProfile: (userId, name) =>
              unawaited(showMemberProfile(context, userId: userId, name: name)),
          onReply: startReply,
          onForward: (message) => unawaited(
            showForwardDialog(
              context,
              message: message,
              sourceServerId: context
                  .read<ServerCubit>()
                  .state
                  .selectedServer
                  ?.id,
              currentPeerId: state.openPeerId,
            ),
          ),
          onEdit: context.read<DmCubit>().editMessage,
          onDelete: context.read<DmCubit>().deleteMessage,
          onRetry: context.read<DmCubit>().retrySend,
          mentionable: _mentionable(state),
        );
      case DmChatStatus.loading:
        return Center(
          child: LoadingDots(color: context.theme.accentBright, dotSize: 6),
        );
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
