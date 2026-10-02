import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/constants.dart';
import '../../../../data/enums/dm_link_state.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
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
import '../../../common/chat/key_change_row.dart';
import '../../../common/chat/pins/show_pinned_messages.dart';
import '../../../common/chat/saved_copy_notice.dart';
import '../../../common/chat/time_out_builder.dart';
import '../../../common/chat/typing_indicator.dart';
import '../../../common/loading_block.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../calls/dm_call_stage.dart';
import '../calls/widgets/dm_call_side_chat_header.dart';
import '../chat/widgets/chat_header.dart';
import '../mobile/widgets/mini_call_bar.dart';
import '../participants_grid/participants_grid.dart';
import '../profile/person/show_person_profile.dart';
import '../profile/person/verification/key_check_gate.dart';
import '../profile/person/verification/key_watch.dart';
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
  String? _peerKey(DmState state) {
    for (final conversation in state.conversations) {
      if (conversation.peerId == state.openPeerId) {
        return conversation.peerChatPublicKey;
      }
    }
    return null;
  }

  /// Whose key this conversation watches — see [KeyWatch].
  static String? _person(DmState state) =>
      state.openPeerId == null ? null : 'server:${state.openPeerId}';

  Future<void> _verify(BuildContext context, DmState state) async {
    final peerId = state.openPeerId;
    final server = context.read<ServerCubit>().state.selectedServer;
    if (peerId == null || server == null) return;
    await showSafetyCodeFor(
      context,
      personName: state.openPeerName ?? '',
      tier: 'server',
      theirId: peerId,
      theirChatKey: _peerKey(state),
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
    // Both asked on every build, so the lookups are registered the same way
    // whether or not there is a call to lay out.
    final wantsExpanded = context.select<AppCubit, bool>(
      (c) => c.state.dmCallExpanded,
    );
    final expanded = stage && wantsExpanded;
    final chatOpen = context.select<AppCubit, bool>(
      (c) => c.state.dmCallChatOpen,
    );

    final conversation = BlocListener<LiveKitCubit, LiveKitState>(
      // Watching a stream is asking for room to watch it in: the call takes
      // the pane, without the messages, and Collapse puts the split back.
      listenWhen: (a, b) =>
          b.subscribedScreenshares.length > a.subscribedScreenshares.length,
      listener: (context, _) {
        if (!stage || expanded) return;
        context.read<AppCubit>().setDmCallExpanded(true, chatOpen: false);
      },
      child: expanded
          ? _expanded(context, state, themeState, chatOpen)
          : LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  ..._top(context, state, callHere),
                  if (stage)
                    DmCallStage(
                      available: constraints.maxHeight - ChatHeader.height,
                    ),
                  ..._conversation(context, state, themeState),
                ],
              ),
            ),
    );
    return KeyWatch(
      person: _person(state),
      chatKey: _peerKey(state),
      child: conversation,
    );
  }

  /// The call given the whole pane. Its own strip carries the name and the
  /// way back, so the conversation's header goes; the messages, when open,
  /// are a panel beside it rather than under it.
  Widget _expanded(
    BuildContext context,
    DmState state,
    ThemeState themeState,
    bool chatOpen,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Expanded(child: ParticipantsGrid()),
      if (chatOpen) ...[
        Container(width: 1, color: themeState.borderPrimary),
        SizedBox(
          width: K.dmCallSideChatWidth,
          child: Column(
            children: [
              DmCallSideChatHeader(
                peerName: state.openPeerName ?? '',
                onClose: context.read<AppCubit>().toggleDmCallChat,
              ),
              ..._conversation(context, state, themeState),
            ],
          ),
        ),
      ],
    ],
  );

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
      keyChanged: context.select<AppCubit, bool>(
        (c) => c.state.seenKeys[_person(state)]?.unacknowledgedChange ?? false,
      ),
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
  ) {
    // The saved copy is on screen while the conversation opens: the
    // composer is there to type into, and sends once the fresh page lands.
    final ready = state.chatStatus == DmChatStatus.ready;
    final composing =
        ready ||
        (state.showingSaved &&
            (state.chatStatus == DmChatStatus.loading ||
                state.chatStatus == DmChatStatus.error));
    return [
      Expanded(child: _buildBody(context, state, themeState)),
      if (!composing) const MiniCallBar(),
      if (state.chatStatus == DmChatStatus.error && state.showingSaved)
        SavedCopyNotice(onRetry: context.read<DmCubit>().retryOpen),
      if (composing) ...[
        TypingIndicator(
          names: state.typingPeerName != null
              ? [state.typingPeerName!]
              : const [],
        ),
        const MiniCallBar(),
        DmComposerSlot(
          state: state,
          composer: KeyCheckGate(
            person: _person(state),
            name: state.openPeerName ?? '',
            onCheck: () => unawaited(_verify(context, state)),
            child: ChatComposer(
              canSend: ready,
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
        ),
      ],
    ];
  }

  /// Send, clearing the reply bar with the same press that clears the field.
  ///
  /// No ping toggle here and none offered: a DM wakes the one person in it
  /// whatever the message says, so a control for whether it does would be a
  /// switch wired to nothing.
  Future<bool> _send(
    BuildContext context,
    String text,
    List<PendingAttachment> attachments,
    PendingLinkPreview? preview,
  ) async {
    final answering = replyingTo;
    final cubit = context.read<DmCubit>();
    cancelReply();
    final refused = await cubit.sendDm(
      text,
      attachments: attachments,
      preview: preview,
      replyToId: answering?.id,
    );
    if (refused && answering != null) restoreReply(answering, pings: true);
    return refused;
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

  /// What the whole server has room for, or null when it has
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

  /// [context] is the one the conversation is being built under — a
  /// `LayoutBuilder`'s, beside a call — not this State's: `context.select`
  /// on the State's context from inside that builder trips the provider's
  /// build-phase assertion.
  Widget _buildBody(
    BuildContext context,
    DmState state,
    ThemeState themeState,
  ) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        return _buildList(context, state, live: true);
      // The saved copy, while the conversation opens or when it could not:
      // drawn as it is, with nothing offered that would act on it.
      case DmChatStatus.loading || DmChatStatus.error when state.showingSaved:
        return _buildList(context, state, live: false);
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

  /// The history. [live] is false for the saved copy: nothing on it is
  /// confirmed, so no row offers an action.
  Widget _buildList(BuildContext context, DmState state, {required bool live}) {
    final cubit = context.read<DmCubit>();
    if (live) syncReplyDraft(state.openPeerId, state.messages);
    // A time-out stops editing, reacting, pinning and forwarding as well
    // as sending, so none of them is offered while it lasts — nor Reply,
    // which only leads to a composer the time-out has taken away. They
    // come back by themselves when it runs out.
    return TimeOutBuilder(
      until: context.select<ServerCubit, DateTime?>(
        (c) => c.state.selectedServer?.user?.timedOutUntil,
      ),
      builder: (context, timedOut) {
        final acting = live && !timedOut;
        return ChatMessageList(
          // Its own list for the saved copy, so the fresh page is primed
          // afresh instead of animating everything since as an arrival.
          key: ValueKey((state.openPeerId, live)),
          messages: state.messages,
          controller: scrollController,
          attachmentLoader: cubit.loadAttachment,
          // Passed either way: it is also what says this surface shows
          // reactions at all. [canReact] is what stops the saved copy taking one.
          onToggleReaction: cubit.toggleReaction,
          onLookUpOriginal: cubit.fetchQuoted,
          onShowAround: live ? cubit.showAround : null,
          viewingHistory: state.hasNewerHistory,
          onReturnToPresent: cubit.returnToPresent,
          onOpenProfile: (userId, name) =>
              unawaited(showMemberProfile(context, userId: userId, name: name)),
          onReply: acting ? startReply : null,
          onForward: acting
              ? (message) => unawaited(
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
                )
              : null,
          onEdit: acting ? cubit.editMessage : null,
          onDelete: live ? cubit.deleteMessage : null,
          onRetry: live ? cubit.retrySend : null,
          canReact: acting,
          onTogglePin: acting
              ? (message) => unawaited(
                  cubit.setPinned(message, pinned: !message.isPinned),
                )
              : null,
          jumpRequests: _jumpRequests,
          mentionable: _mentionable(state),
          calls: state.calls,
          myId: context.read<ServerCubit>().state.selectedServer?.user?.id,
          keyChanges: KeyChangeLines(
            name: state.openPeerName ?? '',
            at: context.select<AppCubit, List<DateTime>>(
              (c) => c.state.seenKeys[_person(state)]?.changes ?? const [],
            ),
            onCheck: () => unawaited(_verify(context, state)),
          ),
        );
      },
    );
  }
}
