import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../common/hint_card.dart';
import 'central_dm_chat_view.dart';
import 'widgets/central_handle_panel.dart';
import 'widgets/dm_list_panel.dart';
import 'widgets/dm_surface.dart';
import 'widgets/new_central_dm_dialog.dart';

/// Home: your central-account DMs.
///
/// Separate from server DMs by design. These belong to your account and
/// follow you between servers, they are quota-limited, and they exist to help
/// people find each other — mixing them into a server's list made it
/// impossible to tell which of those rules applied to a conversation.
class CentralDmView extends StatelessWidget {
  const CentralDmView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CentralDmCubit>().state;
    final ready = state.status == CentralDmStatus.ready;

    return DmSurface(
      emptyIcon: Icons.public,
      emptyTitle: 'Your central DMs',
      emptyMessage: 'Find someone by handle to start a conversation.',
      conversation: state.openPeerId != null ? const CentralDmChatView() : null,
      list: DmListPanel(
        title: 'Direct Messages',
        subtitle: state.myHandle != null
            ? '@${state.myHandle}'
            : 'central account',
        conversations: state.conversations,
        openPeerId: state.openPeerId,
        onNew: ready ? () => NewCentralDmDialog.show(context) : null,
        slot: _buildSlot(state),
        emptyState: _buildEmptyState(state),
        // Says what this tier is *for*, standing under the list rather than
        // only appearing once it's empty — the rule it states applies most
        // when there are conversations to move.
        footer: state.status == CentralDmStatus.ready
            ? const HintCard(
                text:
                    'Central DMs are for finding each other. For longer '
                    'chats, move to a server you share.',
              )
            : null,
        onOpen: (c) {
          // Only one DM surface is open at a time.
          context.read<DmCubit>().closeConversation();
          context.read<CentralDmCubit>().openConversation(
            peerId: c.peerId,
            peerHandle: c.peerName,
            peerChatKey: c.peerChatPublicKey,
            peerSigningKey: c.peerSigningPublicKey,
          );
        },
      ),
    );
  }

  /// Claiming a handle is the one thing that has to happen before this tier
  /// works at all, so it sits above the list rather than inside it.
  Widget? _buildSlot(CentralDmState state) {
    final needsHandle =
        state.status == CentralDmStatus.needsHandle || state.claiming;
    return needsHandle ? const CentralHandlePanel() : null;
  }

  Widget? _buildEmptyState(CentralDmState state) {
    switch (state.status) {
      case CentralDmStatus.signedOut:
        return const HintCard(
          icon: Icons.cloud_off_outlined,
          text:
              'Sign in to your Rift account (Settings → Cloud Backup) to '
              'message people across servers.',
        );
      case CentralDmStatus.needsHandle:
        return null;
      default:
        return const HintCard(
          icon: Icons.alternate_email_rounded,
          text:
              'Find people by handle and say hi — then move long '
              'conversations to a server you share.',
        );
    }
  }
}
