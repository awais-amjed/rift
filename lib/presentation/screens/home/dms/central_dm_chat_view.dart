import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/chat/composer/chat_composer.dart';
import '../../../common/chat/chat_message_list.dart';
import '../../../common/chat/chat_scroll_load_more.dart';
import 'widgets/dm_chat_header.dart';
import 'widgets/quota_meter.dart';
import '../../../theme/app_text.dart';

/// The open central-DM conversation. Central is the discovery funnel:
/// the composer footer shows the daily quota, and sends stop at zero.
class CentralDmChatView extends StatefulWidget {
  const CentralDmChatView({super.key});

  @override
  State<CentralDmChatView> createState() => _CentralDmChatViewState();
}

class _CentralDmChatViewState extends State<CentralDmChatView>
    with ChatScrollLoadMore<CentralDmChatView> {
  @override
  void loadMoreHistory() => context.read<CentralDmCubit>().loadMoreHistory();

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final quotaEmpty = state.remaining != null && state.remaining! <= 0;

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
        if (state.chatStatus == DmChatStatus.ready)
          ChatComposer(
            hintText: quotaEmpty
                ? 'Daily limit reached — continue on a shared server'
                : 'Message @${state.openPeerHandle ?? ''}',
            enabled: !quotaEmpty,
            maxAttachmentBytes: ServerLimits.centralMaxAttachmentBytes,
            footer: const QuotaMeter(),
            onSend: (text, attachments) => context
                .read<CentralDmCubit>()
                .sendDm(text, attachments: attachments),
          ),
      ],
    );
  }

  Widget _buildBody(CentralDmState state, ThemeState themeState) {
    switch (state.chatStatus) {
      case DmChatStatus.ready:
        return ChatMessageList(
          key: ValueKey(state.openPeerId),
          messages: state.messages,
          controller: scrollController,
          attachmentLoader: context.read<CentralDmCubit>().loadAttachment,
          // No onToggleReaction: central DMs are the first-contact tier and are
          // kept deliberately thin — reactions live on servers.
          onEdit: context.read<CentralDmCubit>().editMessage,
          onDelete: context.read<CentralDmCubit>().deleteMessage,
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
