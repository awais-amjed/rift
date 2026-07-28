import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/typing_indicator.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_status_view.dart';

/// Center-pane chat for the open text channel: header, message history,
/// composer. All content shown here has already been decrypted and
/// signature-verified by ChannelChatCubit.
class ChannelChatView extends StatefulWidget {
  const ChannelChatView({super.key});

  @override
  State<ChannelChatView> createState() => _ChannelChatViewState();
}

class _ChannelChatViewState extends State<ChannelChatView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// The list is reversed, so "scrolled to the oldest message" is the far end
  /// of the scroll extent — load the next history page shortly before it.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      context.read<ChannelChatCubit>().loadMoreHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ChannelChatCubit, ChannelChatState>(
          builder: (context, chatState) {
            return Container(
              color: themeState.bgPrimary,
              child: Column(
                children: [
                  const ChatHeader(),
                  Expanded(child: _buildBody(context, chatState)),
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

  Widget _buildBody(BuildContext context, ChannelChatState chatState) {
    switch (chatState.status) {
      case ChannelChatStatus.ready:
        return ChatMessageList(
          key: ValueKey(chatState.channelId),
          messages: chatState.messages,
          controller: _scrollController,
          attachmentLoader: context.read<ChannelChatCubit>().loadAttachment,
          onToggleReaction: context.read<ChannelChatCubit>().toggleReaction,
        );
      case ChannelChatStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ChannelChatStatus.waitingForKey:
        return const ChatStatusView(
          icon: Icons.key_outlined,
          title: 'Waiting for channel access',
          message: 'Another member needs to come online to grant you the '
              'encryption key for this channel.',
          showRetry: true,
        );
      case ChannelChatStatus.error:
        return ChatStatusView(
          icon: Icons.error_outline,
          title: 'Could not open this channel',
          message: chatState.error ?? 'Something went wrong.',
          showRetry: true,
        );
      case ChannelChatStatus.closed:
        return const SizedBox.shrink();
    }
  }
}
