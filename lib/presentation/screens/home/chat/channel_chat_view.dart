import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/mentions.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/chat_failure.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/typing_indicator.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_read_only_banner.dart';
import 'widgets/chat_status_view.dart';

/// Center-pane chat for the open text channel: header, message history,
/// composer. All content shown here has already been decrypted and
/// signature-verified by ChannelChatCubit.
class ChannelChatView extends StatefulWidget {
  const ChannelChatView({super.key});

  @override
  State<ChannelChatView> createState() => _ChannelChatViewState();
}

class _ChannelChatViewState extends State<ChannelChatView>
    with ChatScrollLoadMore<ChannelChatView> {
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
                  // Sending needs the key too, so read-only gets the banner
                  // in the composer's place rather than a composer that would
                  // refuse every message typed into it.
                  if (chatState.status == ChannelChatStatus.readOnly)
                    const ChatReadOnlyBanner(),
                  if (chatState.status == ChannelChatStatus.ready) ...[
                    TypingIndicator(
                      names: chatState.typingUsers.values.toList(),
                      themeState: themeState,
                    ),
                    ChatComposer(
                      onSend: (text, attachments) =>
                          _send(context, text, attachments),
                      onTyping: () =>
                          context.read<ChannelChatCubit>().notifyTyping(),
                      maxAttachmentBytes: _maxAttachmentBytes(context),
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
  ) async {
    // Read at send time rather than watched: joining a call should not rebuild
    // the composer.
    final inVoice = context.read<LiveKitCubit>().state.currentChannelId;
    final voiceBots = context.read<VoiceListenersCubit>();

    await context.read<ChannelChatCubit>().sendMessage(
      text,
      attachments: attachments,
      inVoiceChannel: inVoice,
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
  /// happen (migration 034).
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
        return ChatMessageList(
          key: ValueKey(chatState.channelId),
          messages: chatState.messages,
          controller: scrollController,
          attachmentLoader: context.read<ChannelChatCubit>().loadAttachment,
          onToggleReaction: context.read<ChannelChatCubit>().toggleReaction,
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
        return const Center(child: CircularProgressIndicator());
      case ChannelChatStatus.waitingForKey:
        return const ChatStatusView(
          icon: Icons.key_outlined,
          title: 'Waiting for channel access',
          message:
              'Another member needs to come online to grant you the '
              'encryption key for this channel.',
          showRetry: true,
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
