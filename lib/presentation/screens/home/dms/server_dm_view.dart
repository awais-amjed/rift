import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/hint_card.dart';
import 'server_dm_chat_view.dart';
import 'widgets/dm_list_panel.dart';
import 'widgets/dm_surface.dart';
import 'widgets/member_search_field.dart';

/// DMs with members of the selected server.
///
/// Reached from the server's own column rather than the rail, because that is
/// what they are: part of this server, gone when you switch away from it, and
/// unlimited in a way central DMs aren't.
class ServerDmView extends StatelessWidget {
  const ServerDmView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DmCubit>().state;
    final server = context.watch<ServerCubit>().state.selectedServer;

    return DmSurface(
      emptyIcon: Icons.dns_outlined,
      emptyTitle: 'Server DMs',
      emptyMessage: server == null
          ? 'Join a server to message its members.'
          : 'Pick a conversation, or start one with a member.',
      conversation: state.openPeerId != null ? const ServerDmChatView() : null,
      list: DmListPanel(
        title: 'Server DMs',
        subtitle: server?.name,
        conversations: state.conversations,
        openPeerId: state.openPeerId,
        search: server != null ? const MemberSearchField() : null,
        emptyState: HintCard(
          icon: server == null
              ? Icons.dns_outlined
              : Icons.chat_bubble_outline_rounded,
          text: server == null
              ? 'Join a server to message its members.'
              : 'No conversations on this server yet. These are unlimited — '
                    'unlike central DMs, they stay on the server.',
        ),
        onOpen: (c) {
          // Only one DM surface is open at a time.
          context.read<CentralDmCubit>().closeConversation();
          context.read<DmCubit>().openConversation(
            peerId: c.peerId,
            peerName: c.peerName,
            peerChatKey: c.peerChatPublicKey,
          );
        },
      ),
    );
  }
}
