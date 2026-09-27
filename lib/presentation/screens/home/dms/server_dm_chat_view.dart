import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/enums/dm_link_state.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/forward/show_forward_dialog.dart';
import '../../../common/chat/pins/show_pinned_messages.dart';
import '../../../common/chat/typing_indicator.dart';
import '../../../common/loading_block.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../calls/dm_call_stage.dart';
import '../mobile/widgets/mini_call_bar.dart';
import '../profile/person/show_person_profile.dart';
import '../profile/person/verification/show_verification.dart';
import 'widgets/dm_chat_header.dart';
import 'widgets/dm_composer_slot.dart';

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
  /// Where the pinned list sends the reader — see `ChatMessageList.jumpRequests`.
  final ValueNotifier<String?> _jumpRequests = ValueNotifier(null);

  @override
  void dispose() {
    _jumpRequests.dispose();
    super.dispose();
  }

  /// Either of the two may pin in a DM, so unpinning is always offered.
  void _showPins(BuildContext context, BuildContext anchor) {
    final cubit = context.read<DmCubit>();
    unawaited(
      showPinnedMessages(
        anchor,
        load: cubit.loadPins,
        onJump: (message) => _jumpRequests.value = message.id,
        onUnpin: (message) => cubit.setPinned(message, pinned: false),
      ),
    );
  }

  @override
  void loadMoreHistory() => context.read<DmCubit>().loadMoreHistory();

  @override
  void loadNewerHistory() => context.read<DmCubit>().loadNewerHistory();

  /// The peer's key, as the conversation list knows it — the same key this
  /// conversation's messages are sealed to.
  Future<void> _verify(BuildContext context, DmState state) async {
    final peerId = state.openPeerId;
    final server = context.read<ServerCubit>().state.selectedServer;
    if (peerId == null || server == null) return;
    String? key;
    for (final conversation in state.conversations) {
      if (conversation.peerId == peerId) {
        key = conversation.peerChatPublicKey;
        break;
      }
    }
    await showSafetyCodeFor(
      context,
      personName: state.openPeerName ?? '',
      tier: 'server',
      theirId: peerId,
      theirChatKey: key,
      myId: server.user?.id ?? '',
      host: Uri.parse(server.supabaseUrl).host,
    );
  }

  /// Whether the open person can be rung from here: an open conversation,
  /// nobody blocked, a person rather than a bot, and a server that has voice
  /// and lets this member use it. The server asks all of this again; this
  /// only keeps a button off the screen that could only be refused.
  bool _canCall(DmState state) {
    final peerId = state.openPeerId;
    final server = context.read<ServerCubit>().state.selectedServer;
    if (peerId == null || server == null || server.livekitUrl == null) {
      return false;
    }
    if (state.openLinkState != DmLinkState.open ||
        state.blockedIds.contains(peerId)) {
      return false;
    }
    if (!(server.user?.permissions.can(ServerPermission.connect) ?? false)) {
      return false;
    }
    final peer = context.read<ServerMembersCubit>().state.byId[peerId];
    return !(peer?.isBot ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<DmCubit>().state;
    final serverId = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServer?.id,
    );
    // This conversation's call, placed or answered on this device — drawn
    // above the messages on a desktop. A phone gives a call its own page.
    final callHere = context.select<LiveKitCubit, bool>((c) {
      final dm = c.state.dmCall;
      return dm != null &&
          dm.serverId == serverId &&
          dm.peerId == state.openPeerId;
    });
    final stage = callHere && !context.layoutMode.isCompact;

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ..._top(context, state, callHere),
          if (stage) DmCallStage(available: constraints.maxHeight),
          ..._conversation(context, state, themeState),
        ],
      ),
    );
  }

  List<Widget> _top(BuildContext context, DmState state, bool callHere) => [
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
      onVerify: state.openPeerId == null
          ? null
          : () => unawaited(_verify(context, state)),
      onShowPins: state.openPeerId == null
          ? null
          : (anchor) => _showPins(context, anchor),
      onCall: callHere || !_canCall(state)
          ? null
          : () => context.read<DmCallCubit>().startCall(
              peerId: state.openPeerId!,
              peerName: state.openPeerName ?? '',
            ),
      onClose: () => context.read<DmCubit>().closeConversation(),
    ),
  ];

  List<Widget> _conversation(
    BuildContext context,
    DmState state,
    ThemeState themeState,
  ) => [
    Expanded(child: _buildBody(state, themeState)),
    if (state.chatStatus != DmChatStatus.ready) const MiniCallBar(),
    if (state.chatStatus == DmChatStatus.ready) ...[
      TypingIndicator(
        names: state.typingPeerName != null
            ? [state.typingPeerName!]
            : const [],
      ),
      const MiniCallBar(),
      DmComposerSlot(
        state: state,
        composer: ChatComposer(
          hintText: 'Message ${state.openPeerName ?? ''}',
          canAttach: _canAttach(),
          maxAttachmentBytes: _maxAttachmentBytes(),
          remainingStorageBytes: _remainingStorage(),
          onSend: (text, attachments, preview) =>
              _send(context, text, attachments, preview),
          replyingTo: replyingTo,
          onCancelReply: cancelReply,
          onTyping: () => context.read<DmCubit>().notifyTyping(),
        ),
      ),
    ],
  ];

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

  /// A server DM's attachments go into the server's own bucket, so the
  /// permission that governs the channels governs these too.
  bool _canAttach() =>
      context.read<ServerCubit>().state.selectedServer?.user?.permissions.can(
        ServerPermission.attachFiles,
      ) ??
      false;

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
          onTogglePin: (message) => unawaited(
            context.read<DmCubit>().setPinned(
              message,
              pinned: !message.isPinned,
            ),
          ),
          jumpRequests: _jumpRequests,
          mentionable: _mentionable(state),
          calls: state.calls,
          myId: context.read<ServerCubit>().state.selectedServer?.user?.id,
        );
      case DmChatStatus.loading:
        return const LoadingBlock();
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
