import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/chat/chat_composer.dart';
import '../../../common/chat/chat_message_list.dart';
import 'widgets/dm_chat_header.dart';
import 'widgets/quota_meter.dart';

/// The open central-DM conversation. Central is the discovery funnel:
/// the composer footer shows the daily quota, and sends stop at zero.
class CentralDmChatView extends StatefulWidget {
  const CentralDmChatView({super.key});

  @override
  State<CentralDmChatView> createState() => _CentralDmChatViewState();
}

class _CentralDmChatViewState extends State<CentralDmChatView> {
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      context.read<CentralDmCubit>().loadMoreHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final state = context.watch<CentralDmCubit>().state;
    final quotaEmpty = state.remaining != null && state.remaining! <= 0;

    return Column(
      children: [
        DmChatHeader(
          icon: Icons.public,
          title: '@${state.openPeerHandle ?? ''}',
          subtitle: 'Central DM — for finding each other',
          onClose: () => context.read<CentralDmCubit>().closeConversation(),
        ),
        Expanded(child: _buildBody(state, themeState)),
        if (state.chatStatus == DmChatStatus.ready)
          ChatComposer(
            hintText: quotaEmpty
                ? 'Daily limit reached — continue on a shared server'
                : 'Message @${state.openPeerHandle ?? ''}',
            enabled: !quotaEmpty,
            footer: const QuotaMeter(),
            onSend: (text) => context.read<CentralDmCubit>().sendDm(text),
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
          controller: _scrollController,
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
              style: TextStyle(fontSize: 13, color: themeState.textTertiary),
            ),
          ),
        );
      case DmChatStatus.closed:
        return const SizedBox.shrink();
    }
  }
}
