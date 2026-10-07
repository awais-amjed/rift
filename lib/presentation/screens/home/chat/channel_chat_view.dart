import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/classes/chat_message.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/classes/user_permissions.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../logic/services/chat_failure.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../../logic/services/mentions.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/drop/chat_drop_zone.dart';
import '../../../common/chat/forward/show_forward_dialog.dart';
import '../../../common/chat/pins/show_pinned_messages.dart';
import '../../../common/chat/polls/create_poll_dialog.dart';
import '../../../common/chat/saved_copy_notice.dart';
import '../../../common/chat/time_out_builder.dart';
import '../../../common/chat/time_out_gate.dart';
import '../../../common/chat/typing_indicator.dart';
import '../../../common/loading_block.dart';
import '../../../theme/theme_context.dart';
import '../mobile/widgets/mini_call_bar.dart';
import '../profile/person/show_person_profile.dart';
import '../reports/show_report_dialog.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_read_only_banner.dart';
import 'widgets/chat_status_view.dart';
import 'widgets/key_holder_list.dart';

/// Over the widget budget and one job: the open channel — header, history and
/// composer, and the states before a channel can be read.
///
/// Center-pane chat for the open text channel: header, message history,
/// composer. All content shown here has already been decrypted and
/// signature-verified by ChannelChatCubit.
class ChannelChatView extends StatefulWidget {
  const ChannelChatView({super.key});

  @override
  State<ChannelChatView> createState() => _ChannelChatViewState();
}

class _ChannelChatViewState extends State<ChannelChatView>
    with ChatScrollLoadMore<ChannelChatView>, ChatReplyDraft<ChannelChatView> {
  /// Where the pinned list sends the reader: set to a message id, and the
  /// message list goes there.
  final ValueNotifier<String?> _jumpRequests = ValueNotifier(null);

  @override
  void dispose() {
    _jumpRequests.dispose();
    super.dispose();
  }

  @override
  void loadMoreHistory() => context.read<ChannelChatCubit>().loadMoreHistory();

  @override
  void loadNewerHistory() =>
      context.read<ChannelChatCubit>().loadNewerHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Watched rather than read: a role edited while the channel is open
    // changes what the composer and the message menus offer, and nothing
    // else here rebuilds for it.
    context.select<ServerCubit, int?>(
      (cubit) => cubit.state.selectedServer?.user?.permissions.bits,
    );
    return BlocBuilder<ChannelChatCubit, ChannelChatState>(
      // Only what decides the frame: which state is drawn and what holds the
      // composer's slot. The history, who is typing and the composer's bots
      // each watch their own part below, so an upload's progress or somebody
      // typing rebuilds what shows it and not the header and composer too.
      buildWhen: (a, b) =>
          a.status != b.status ||
          a.showingSaved != b.showingSaved ||
          a.channelId != b.channelId ||
          a.failure != b.failure,
      builder: (context, chatState) {
        final status = chatState.status;
        // The saved copy is on screen and the channel is still opening: the
        // composer is there to type into, and sends once the keyring lands.
        // And kept when the open fails, under the notice saying so, so what
        // was typed while it tried is still there for the retry.
        final opening =
            chatState.showingSaved &&
            (status == ChannelChatStatus.loading ||
                status == ChannelChatStatus.healingKey ||
                status == ChannelChatStatus.error);
        final composing = status == ChannelChatStatus.ready || opening;
        // No background of its own: the content panel it sits in owns
        // that, and painting over it would break the panel's rounding.
        return DefaultTextStyle.merge(
          style: TextStyle(color: themeState.textSecondary),
          child: ChatDropZone(
            child: Column(
              children: [
                ChatHeader(
                  onShowPins: chatState.channelId == null
                      ? null
                      : (anchor) => _showPins(context, anchor),
                ),
                Expanded(child: _buildBody(context, chatState)),
                // A phone's way back into the call, just above whatever
                // holds the composer's slot. Nothing on a desktop.
                if (!composing) const MiniCallBar(),
                // Sending needs the key too, so read-only gets the banner
                // in the composer's place rather than a composer that would
                // refuse every message typed into it.
                // Waiting keeps the slot too: a composer that is plainly
                // coming says "this will work later", where an absent one
                // says this channel has none.
                if (status == ChannelChatStatus.readOnly)
                  const ChatReadOnlyBanner()
                else if (status == ChannelChatStatus.waitingForKey)
                  const ChatReadOnlyBanner(waitingForKey: true)
                else if (status == ChannelChatStatus.error &&
                    chatState.showingSaved)
                  SavedCopyNotice(
                    onRetry: context.read<ChannelChatCubit>().retry,
                  ),
                if (composing) ...[
                  BlocSelector<
                    ChannelChatCubit,
                    ChannelChatState,
                    Map<String, String>
                  >(
                    selector: (s) => s.typingUsers,
                    builder: (context, typing) =>
                        TypingIndicator(names: typing.values.toList()),
                  ),
                  const MiniCallBar(),
                  TimeOutGate(
                    until: context.select<ServerCubit, DateTime?>(
                      (c) => c.state.selectedServer?.user?.timedOutUntil,
                    ),
                    child: ChatComposer(
                      canSend: status == ChannelChatStatus.ready,
                      onSend: (text, attachments, preview) =>
                          _send(context, text, attachments, preview),
                      replyingTo: replyingTo,
                      onCancelReply: cancelReply,
                      // A channel is the one surface with somebody to ring
                      // who is not already being written to.
                      replyPings: replyPings,
                      onToggleReplyPing: setReplyPing,
                      onTyping: () =>
                          context.read<ChannelChatCubit>().notifyTyping(),
                      canAttach: _canAttach(context),
                      maxAttachmentBytes: _maxAttachmentBytes(context),
                      remainingStorageBytes: _remainingStorage(context),
                      // Every file goes as it is where encryption is off, so
                      // there is no choice to offer per file.
                      offersPlainFiles: !_notEncrypted(context),
                      notEncrypted: _notEncrypted(context),
                      bots: context.select(
                        (ChannelChatCubit c) => c.state.bots,
                      ),
                      onCreatePoll: _canCreatePoll(context)
                          ? () => _createPoll(context)
                          : null,
                      onMentionSearch: (query) =>
                          _searchMentionable(context, query),
                      selfUserId: context
                          .read<ServerCubit>()
                          .state
                          .selectedServer
                          ?.user
                          ?.id,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Send, and re-read the summons if the line could have changed them.
  ///
  /// A `/` command sent from inside a call may summon a bot or send one away,
  /// and the sidebar draws a summoned-but-absent bot from that row. Narrowed to
  /// a slash typed while in a call rather than run on every message: it is the
  /// only shape that can change one, and a query per message to catch it would
  /// be a poor trade.
  Future<bool> _send(
    BuildContext context,
    String text,
    List<PendingAttachment> attachments,
    Future<PendingLinkPreview?>? preview,
  ) async {
    // Read at send time rather than watched: joining a call should not rebuild
    // the composer.
    final inVoice = context.read<LiveKitCubit>().state.currentChannelId;
    final voiceBots = context.read<VoiceListenersCubit>();

    // Read before the send and cleared after it: the composer is emptied by
    // the same press, and a reply bar still standing over an empty field is
    // the next message quietly joining a thread it was not meant for. A
    // refusal puts both back.
    final answering = replyingTo;
    final pings = replyPings;
    cancelReply();

    final refused = await context.read<ChannelChatCubit>().sendMessage(
      text,
      attachments: attachments,
      preview: preview,
      inVoiceChannel: inVoice,
      replyToId: answering?.id,
      pingReplyTo: pings,
    );
    if (refused && answering != null) restoreReply(answering, pings: pings);

    if (inVoice != null && text.trimLeft().startsWith('/')) {
      await voiceBots.refresh();
    }
    return refused;
  }

  /// Carry a message somewhere else.
  ///
  /// The server id goes along only so the attachment bytes can be fetched
  /// from the bucket they are in. It is not written into the message —
  /// naming this channel would tell readers elsewhere that it exists.
  void _showPins(BuildContext context, BuildContext anchor) {
    final cubit = context.read<ChannelChatCubit>();
    final canPin = _canPin(context, cubit.state.channelId);
    unawaited(
      showPinnedMessages(
        anchor,
        load: cubit.loadPins,
        onJump: (message) => _jumpRequests.value = message.id,
        displayNames: cubit.state.mentionNames,
        onUnpin: canPin
            ? (message) => cubit.setPinned(message, pinned: false)
            : null,
      ),
    );
  }

  void _createPoll(BuildContext context) {
    final cubit = context.read<ChannelChatCubit>();
    unawaited(
      showCreatePollDialog(
        context,
        onPost: (body, multiple, duration) =>
            cubit.sendPoll(body, multiple: multiple, duration: duration),
      ),
    );
  }

  void _forward(
    BuildContext context,
    ChatMessage message,
    ChannelChatState chatState,
  ) {
    unawaited(
      showForwardDialog(
        context,
        message: message,
        sourceServerId: context.read<ServerCubit>().state.selectedServer?.id,
        currentChannelId: chatState.channelId,
      ),
    );
  }

  /// Who the `@` menu may offer for what has been typed after the `@`.
  ///
  /// Asked of the database with the channel, so a private one offers only the
  /// people who can open it. Doing it any other way means being a second copy
  /// of `channel_eligible`, and the server strips a mention of an outsider on
  /// the way in anyway — so offering them was offering a ping that would not
  /// happen.
  ///
  /// **People, not bots.** A bot is addressed with `/`, which has its own menu
  /// one key away; offering it here would teach the `@bot` habit and then
  /// silently do nothing with it (BOTS.md §4). The sender and banned members
  /// are dropped by the menu itself.
  Future<List<ServerMember>> _searchMentionable(
    BuildContext context,
    String query,
  ) {
    final channelId = context.read<ChannelChatCubit>().state.channelId;
    if (channelId == null) return Future.value(const []);
    return context.read<ServerCubit>().searchMembers(
      query: query,
      channelId: channelId,
      bots: false,
    );
  }

  /// The operator's per-file attachment cap for this server.
  int _maxAttachmentBytes(BuildContext context) =>
      (context.read<ServerCubit>().state.selectedServer?.limits ??
              ServerLimits.defaults)
          .maxAttachmentBytes;

  /// What the whole server has room for, or null when it has
  /// no storage limit.
  int? _remainingStorage(BuildContext context) {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return null;
    return server.limits.remainingStorage(server.storageUsed);
  }

  /// The open channel, once the server's channel list has it.
  Channel? _channel(BuildContext context, String? channelId) => context
      .read<ServerCubit>()
      .state
      .selectedServer
      ?.channels
      .where((c) => c.id == channelId)
      .firstOrNull;

  /// Channel managers and server admins may delete anyone's message here.
  bool _isModerator(BuildContext context) {
    final permissions = _myPermissions(context);
    return (permissions?.isChannelManager ?? false) ||
        (permissions?.isServerAdmin ?? false);
  }

  UserPermissions? _myPermissions(BuildContext context) =>
      context.read<ServerCubit>().state.selectedServer?.user?.permissions;

  /// Asked here rather than inside the list, because the answer is the
  /// server's and a DM surface has no roles to ask about. The database
  /// refuses the row either way (`message_reactions_insert`); this is so the
  /// button is not offered in the first place.
  bool _canReact(BuildContext context) =>
      _myPermissions(context)?.can(ServerPermission.addReactions) ?? false;

  bool _canAttach(BuildContext context) =>
      _myPermissions(context)?.can(ServerPermission.attachFiles) ?? false;

  /// Whether the open channel's encryption was turned off. Watched, so the
  /// composer changes the moment somebody switches it.
  bool _notEncrypted(BuildContext context) {
    final channelId = context.select(
      (ChannelChatCubit c) => c.state.channelId,
    );
    return context.select(
      (ServerCubit c) =>
          c.state.selectedServer?.channels
              .where((ch) => ch.id == channelId)
              .firstOrNull
              ?.isEncrypted ==
          false,
    );
  }

  bool _canCreatePoll(BuildContext context) =>
      _myPermissions(context)?.can(ServerPermission.createPolls) ?? false;

  /// The server's rule (`app.can_pin_in`), asked here only to decide whether
  /// to offer it: the bit, or managing this channel if it is a private one.
  bool _canPin(BuildContext context, String? channelId) {
    if (_myPermissions(context)?.can(ServerPermission.pinMessages) ?? false) {
      return true;
    }
    final channel = _channel(context, channelId);
    return channel != null && channel.isPrivate && channel.canManage;
  }

  Widget _buildBody(BuildContext context, ChannelChatState chatState) {
    switch (chatState.status) {
      // Read-only renders the same list. What it can open, it opens; what it
      // cannot comes back as a locked row, so the history is visible as
      // history rather than as an absence.
      case ChannelChatStatus.ready:
      case ChannelChatStatus.readOnly:
        return _history(live: true);
      // The saved copy, while the channel opens or when it could not: drawn
      // as it is, with nothing offered that would act on it.
      case ChannelChatStatus.loading ||
              ChannelChatStatus.healingKey ||
              ChannelChatStatus.error
          when chatState.showingSaved:
        return _history(live: false);
      case ChannelChatStatus.loading:
      // Drawn the same as loading, and that is the whole point: a key being
      // wrapped for a new member is work in progress, not a refusal.
      case ChannelChatStatus.healingKey:
        return const LoadingBlock();
      case ChannelChatStatus.waitingForKey:
        final channel = _channel(context, chatState.channelId);
        return ChatStatusView(
          icon: Icons.key_rounded,
          title: 'Waiting for the channel key',
          // Why it is waiting, and that nobody has to do anything: stating
          // the state alone left people unsure whether they were meant to act,
          // which is what made it read as broken.
          message: channel == null
              ? 'A member who already has the key has to be online for it to '
                    'be handed to you — this happens automatically, and '
                    'nothing here needs doing.'
              : 'You\'ve been added to #${channel.name}. A member who already '
                    'has the key has to be online for it to be handed to you — '
                    'this happens automatically, and nothing here needs doing.',
          listening: 'Listening for a key holder',
          detail: channel == null
              ? null
              : KeyHolderList(key: ValueKey(channel.id), channel: channel),
        );
      case ChannelChatStatus.error:
        final failure = chatState.failure ?? const ChatFailure.unknown();
        return ChatStatusView(
          // An unreachable server is worth its own icon: the error glyph reads
          // as "Rift broke", and this one is almost always the server being
          // down rather than anything wrong with the channel.
          icon: failure.offline ? Icons.cloud_off_rounded : Icons.error_outline,
          title: failure.title,
          message: failure.message,
          showRetry: true,
        );
      case ChannelChatStatus.closed:
        return const SizedBox.shrink();
    }
  }

  /// The history, rebuilt for what the list draws and nothing else.
  Widget _history({required bool live}) =>
      BlocBuilder<ChannelChatCubit, ChannelChatState>(
        buildWhen: (a, b) =>
            !identical(a.messages, b.messages) ||
            !identical(a.mentionNames, b.mentionNames) ||
            !identical(a.pollTallies, b.pollTallies) ||
            a.hasNewerHistory != b.hasNewerHistory ||
            a.status != b.status ||
            a.channelId != b.channelId,
        builder: (context, chatState) =>
            _buildList(context, chatState, live: live),
      );

  /// The history. [live] is false for the saved copy: every action on a row
  /// is withheld, since none of it is confirmed and the keys to act with are
  /// still being fetched.
  Widget _buildList(
    BuildContext context,
    ChannelChatState chatState, {
    required bool live,
  }) {
    final cubit = context.read<ChannelChatCubit>();
    if (live) syncReplyDraft(chatState.channelId, chatState.messages);
    // A time-out stops posting, editing, reacting and pinning
    // (`app.timed_out` in the policies), so none of them is offered while
    // it lasts — nor Reply, which only leads to the composer the banner
    // has replaced. They come back by themselves when it runs out.
    return TimeOutBuilder(
      until: context.select<ServerCubit, DateTime?>(
        (c) => c.state.selectedServer?.user?.timedOutUntil,
      ),
      builder: (context, timedOut) {
        final acting = live && !timedOut;
        return ChatMessageList(
          // A list of its own for the saved copy. The fresh page then starts
          // a new one, primed afresh, rather than animating everything sent
          // since the copy was saved as if it had just arrived.
          key: ValueKey((chatState.channelId, live)),
          messages: chatState.messages,
          controller: scrollController,
          attachmentLoader: cubit.attachmentLoader,
          // Passed either way: it is also what says this surface shows
          // reactions at all. [canReact] is what stops the saved copy taking one.
          onToggleReaction: cubit.toggleReaction,
          onLookUpOriginal: cubit.fetchQuoted,
          onShowAround: live ? cubit.showAround : null,
          viewingHistory: chatState.hasNewerHistory,
          onReturnToPresent: cubit.returnToPresent,
          onOpenProfile: (userId, name) =>
              unawaited(showMemberProfile(context, userId: userId, name: name)),
          onReply: acting ? startReply : null,
          onForward: acting
              ? (message) => _forward(context, message, chatState)
              : null,
          onEdit: acting ? cubit.editMessage : null,
          onDelete: live ? cubit.deleteMessage : null,
          onRetry: live ? cubit.retrySend : null,
          onPanelAction: live ? cubit.pressPanelAction : null,
          // Channel managers and admins may remove anyone's message.
          isModerator: live && _isModerator(context),
          canReact: acting && _canReact(context),
          // Only the names these messages actually say, resolved against this
          // channel — see [ChannelChatState.mentionNames]. `@all` is added
          // here because it names everybody in the room and so lights up like
          // a name that reached somebody; nobody can be called it, so it is
          // never ambiguous between the room and a person.
          mentionable: {Mentions.everyone, ...chatState.mentionNames.keys},
          mentionNames: chatState.mentionNames,
          onReport: live
              ? (message) =>
                    unawaited(showReportMessageDialog(context, message))
              : null,
          onTogglePin: acting && _canPin(context, chatState.channelId)
              ? (message) => unawaited(
                  cubit.setPinned(message, pinned: !message.isPinned),
                )
              : null,
          pollTallies: chatState.pollTallies,
          // Voting needs no key, but a read-only seat is one that cannot send,
          // and a vote is the one thing here that is sent.
          onVote: chatState.status == ChannelChatStatus.ready
              ? cubit.vote
              : null,
          onClosePoll: live ? cubit.closePoll : null,
          jumpRequests: _jumpRequests,
        );
      },
    );
  }
}
