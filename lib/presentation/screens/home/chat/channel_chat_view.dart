import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../logic/services/chat_failure.dart';
import '../../../../logic/services/link_preview_fetcher.dart';
import '../../../../logic/services/mentions.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_reply_draft.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/typing_indicator.dart';
import '../mobile/widgets/mini_call_bar.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_read_only_banner.dart';
import 'widgets/chat_status_view.dart';
import 'widgets/key_holder_list.dart';

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
  @override
  void loadMoreHistory() => context.read<ChannelChatCubit>().loadMoreHistory();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ChannelChatCubit, ChannelChatState>(
          builder: (context, chatState) {
            // No background of its own: the content panel it sits in owns
            // that, and painting over it would break the panel's rounding.
            return DefaultTextStyle.merge(
              style: TextStyle(color: themeState.textSecondary),
              child: Column(
                children: [
                  const ChatHeader(),
                  Expanded(child: _buildBody(context, chatState)),
                  // A phone's way back into the call, just above whatever
                  // holds the composer's slot. Nothing on a desktop.
                  if (chatState.status != ChannelChatStatus.ready)
                    const MiniCallBar(),
                  // Sending needs the key too, so read-only gets the banner
                  // in the composer's place rather than a composer that would
                  // refuse every message typed into it.
                  // Waiting keeps the slot too: a composer that is plainly
                  // coming says "this will work later", where an absent one
                  // says this channel has none.
                  if (chatState.status == ChannelChatStatus.readOnly)
                    const ChatReadOnlyBanner()
                  else if (chatState.status == ChannelChatStatus.waitingForKey)
                    const ChatReadOnlyBanner(waitingForKey: true),
                  if (chatState.status == ChannelChatStatus.ready) ...[
                    TypingIndicator(
                      names: chatState.typingUsers.values.toList(),
                    ),
                    const MiniCallBar(),
                    ChatComposer(
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
                      maxAttachmentBytes: _maxAttachmentBytes(context),
                      remainingStorageBytes: _remainingStorage(context),
                      bots: chatState.bots,
                      onMentionSearch: (query) =>
                          _searchMentionable(context, query),
                      selfUserId: context
                          .read<ServerCubit>()
                          .state
                          .selectedServer
                          ?.user
                          ?.id,
                    ),
                  ],
                ],
              ),
            );
          },
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
  Future<void> _send(
    BuildContext context,
    String text,
    List<PendingAttachment> attachments,
    PendingLinkPreview? preview,
  ) async {
    // Read at send time rather than watched: joining a call should not rebuild
    // the composer.
    final inVoice = context.read<LiveKitCubit>().state.currentChannelId;
    final voiceBots = context.read<VoiceListenersCubit>();

    // Read before the send and cleared after it: the composer is emptied by
    // the same press, and a reply bar still standing over an empty field is
    // the next message quietly joining a thread it was not meant for.
    final answering = replyToId;
    final pings = replyPings;
    cancelReply();

    await context.read<ChannelChatCubit>().sendMessage(
      text,
      attachments: attachments,
      preview: preview,
      inVoiceChannel: inVoice,
      replyToId: answering,
      pingReplyTo: pings,
    );

    if (inVoice != null && text.trimLeft().startsWith('/')) {
      await voiceBots.refresh();
    }
  }

  /// Who the `@` menu may offer for what has been typed after the `@`.
  ///
  /// Asked of the database with the channel, so a private one offers only the
  /// people who can open it. Doing it any other way means being a second copy
  /// of `channel_eligible`, and the server strips a mention of an outsider on
  /// the way in anyway — so offering them was offering a ping that would not
  /// happen (`010_bot_permissions.sql`).
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

  /// What the whole server has room for (migration 029), or null when it has
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
    final permissions = context
        .read<ServerCubit>()
        .state
        .selectedServer
        ?.user
        ?.permissions;
    return (permissions?.isChannelManager ?? false) ||
        (permissions?.isServerAdmin ?? false);
  }

  Widget _buildBody(BuildContext context, ChannelChatState chatState) {
    switch (chatState.status) {
      // Read-only renders the same list. What it can open, it opens; what it
      // cannot comes back as a locked row, so the history is visible as
      // history rather than as an absence.
      case ChannelChatStatus.ready:
      case ChannelChatStatus.readOnly:
        syncReplyDraft(chatState.channelId, chatState.messages);
        return ChatMessageList(
          key: ValueKey(chatState.channelId),
          messages: chatState.messages,
          controller: scrollController,
          attachmentLoader: context.read<ChannelChatCubit>().loadAttachment,
          onToggleReaction: context.read<ChannelChatCubit>().toggleReaction,
          onReply: startReply,
          onEdit: context.read<ChannelChatCubit>().editMessage,
          onDelete: context.read<ChannelChatCubit>().deleteMessage,
          onRetry: context.read<ChannelChatCubit>().retrySend,
          onPanelAction: context.read<ChannelChatCubit>().pressPanelAction,
          // Channel managers and admins may remove anyone's message.
          isModerator: _isModerator(context),
          // Only the names these messages actually say, resolved against this
          // channel — see [ChannelChatState.mentionNames]. `@all` is added
          // here because it names everybody in the room and so lights up like
          // a name that reached somebody; nobody can be called it, so it is
          // never ambiguous between the room and a person.
          mentionable: {Mentions.everyone, ...chatState.mentionNames.keys},
          mentionNames: chatState.mentionNames,
        );
      case ChannelChatStatus.loading:
      // Drawn the same as loading, and that is the whole point: a key being
      // wrapped for a new member is work in progress, not a refusal.
      case ChannelChatStatus.healingKey:
        return const Center(child: CircularProgressIndicator());
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
}
