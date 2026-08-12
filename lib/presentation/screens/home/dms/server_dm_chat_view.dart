import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import '../../../common/chat/typing_indicator.dart';
import 'widgets/dm_chat_header.dart';
import '../../../theme/app_text.dart';

/// The open server-DM conversation: header + history + composer, on the
/// shared chat kit.
class ServerDmChatView extends StatefulWidget {
  const ServerDmChatView({super.key});

  @override
  State<ServerDmChatView> createState() => _ServerDmChatViewState();
}

class _ServerDmChatViewState extends State<ServerDmChatView>
    with ChatScrollLoadMore<ServerDmChatView> {
  @override
  void loadMoreHistory() => context.read<DmCubit>().loadMoreHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<DmCubit>().state;

    return Column(
      children: [
        DmChatHeader(
          tierIcon: Icons.dns_outlined,
          tierLabel: 'Server',
          title: state.openPeerName ?? '',
          peerId: state.openPeerId,
          onClose: () => context.read<DmCubit>().closeConversation(),
        ),
        Expanded(child: _buildBody(state, themeState)),
        if (state.chatStatus == DmChatStatus.ready) ...[
          TypingIndicator(
            names: state.typingPeerName != null
                ? [state.typingPeerName!]
                : const [],
            themeState: themeState,
          ),
          ChatComposer(
            hintText: 'Message ${state.openPeerName ?? ''}',
            maxAttachmentBytes: _maxAttachmentBytes(),
            onSend: (text, attachments) =>
                context.read<DmCubit>().sendDm(text, attachments: attachments),
            onTyping: () => context.read<DmCubit>().notifyTyping(),
          ),
        ],
      ],
    );
  }

  /// The operator's per-file attachment cap for this server.
  int _maxAttachmentBytes() =>
      (context.read<ServerCubit>().state.selectedServer?.limits ??
              ServerLimits.defaults)
          .maxAttachmentBytes;

  Widget _buildBody(DmState state, ThemeState themeState) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        return ChatMessageList(
          key: ValueKey(state.openPeerId),
          messages: state.messages,
          controller: scrollController,
          attachmentLoader: context.read<DmCubit>().loadAttachment,
          onToggleReaction: context.read<DmCubit>().toggleReaction,
          onEdit: context.read<DmCubit>().editMessage,
          onDelete: context.read<DmCubit>().deleteMessage,
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
              style: AppText.rowQuiet.copyWith(
                fontSize: 13,
                color: themeState.textTertiary,
              ),
            ),
          ),
        );
      case DmChatStatus.closed:
        return const SizedBox.shrink();
    }
  }
}
