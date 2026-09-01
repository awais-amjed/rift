import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_limits.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
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
                      onSend: (text, attachments) => context
                          .read<ChannelChatCubit>()
                          .sendMessage(text, attachments: attachments),
                      onTyping: () =>
                          context.read<ChannelChatCubit>().notifyTyping(),
                      maxAttachmentBytes: _maxAttachmentBytes(context),
                      bots: _bots(context),
                      mentionable: _mentionableMembers(context),
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

  /// Username → display name, so a mention draws as the name the room knows.
  ///
  /// Keyed by username because that is what the message contains; the value is
  /// only ever what gets drawn. A member who has left is absent, and their
  /// mention stays as written rather than becoming somebody else.
  Map<String, String> _mentionNames(BuildContext context) {
    final members = context.watch<ServerMembersCubit>().state.members;
    return {
      for (final m in members ?? const <ServerMember>[])
        m.username.toLowerCase(): m.displayName,
    };
  }

  /// Everybody the composer's `@` menu may offer.
  ///
  /// The whole roster, bots included — a bot is addressed by name like anyone
  /// else. Banned members are dropped by the menu itself, which is also where
  /// the sender is left out.
  List<ServerMember> _mentionableMembers(BuildContext context) =>
      context.watch<ServerMembersCubit>().state.members ?? const [];

  /// The bots on this server, for the composer's `/` menu.
  ///
  /// Banned ones are dropped here rather than in the composer: the server
  /// refuses a command addressed to one (`app.is_addressable_bot`), so
  /// offering it would be offering a send that comes back rejected.
  List<ServerMember> _bots(BuildContext context) => [
    for (final m
        in context.watch<ServerMembersCubit>().state.members ??
            const <ServerMember>[])
      if (m.isBot && !m.isBanned) m,
  ];

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

  /// Everyone an `@mention` can reach in this channel: the server's roster, by
  /// username.
  ///
  /// Usernames rather than display names, because a display name can be
  /// changed by its owner at any time and can collide with another member's —
  /// neither of which is a property you want deciding who got pinged.
  Set<String> _mentionable(BuildContext context) {
    final members = context.watch<ServerMembersCubit>().state.members;
    return {
      // `@all` reaches everybody in the room, so it is a name that reaches
      // somebody and gets lit like one. Nobody can be called this — see
      // `users_username_not_reserved` in migration 012 — so it is never
      // ambiguous between the room and a person.
      Mentions.everyone,
      for (final m in members ?? const []) m.username.toLowerCase(),
    };
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
          onPanelAction: context.read<ChannelChatCubit>().pressPanelAction,
          // Channel managers and admins may remove anyone's message.
          isModerator: _isModerator(context),
          mentionable: _mentionable(context),
          mentionNames: _mentionNames(context),
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
