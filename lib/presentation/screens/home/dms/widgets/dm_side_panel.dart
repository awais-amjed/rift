import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart'
    as central;
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import 'central_handle_panel.dart';
import 'dm_conversation_tile.dart';
import 'new_central_dm_dialog.dart';
import 'new_server_dm_dialog.dart';

/// Left panel of the Home surface: central conversations (globe) and
/// selected-server conversations (server tier), each with a "new
/// conversation" action.
class DmSidePanel extends StatelessWidget {
  const DmSidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final centralState = context.watch<central.CentralDmCubit>().state;
    final dmState = context.watch<DmCubit>().state;
    final serverName = context.watch<ServerCubit>().state.selectedServer?.name;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Central tier ─────────────────────────────────────
        _SectionHeader(
          themeState: themeState,
          icon: Icons.public,
          label: 'Central',
          onAdd: centralState.status == central.CentralDmStatus.ready
              ? () => NewCentralDmDialog.show(context)
              : null,
        ),
        const SizedBox(height: 4),
        if (centralState.status == central.CentralDmStatus.signedOut)
          _HintText(
            themeState: themeState,
            text:
                'Sign in to your Rift account (Settings → Backup) to '
                'message people across servers.',
          )
        else if (centralState.status == central.CentralDmStatus.needsHandle ||
            centralState.claiming)
          const CentralHandlePanel()
        else if (centralState.conversations.isEmpty)
          _HintText(
            themeState: themeState,
            text:
                'Find people by handle and say hi — then move long '
                'conversations to a server you share.',
          )
        else
          ...centralState.conversations.map(
            (c) => DmConversationTile(
              conversation: c,
              icon: Icons.public,
              isSelected: centralState.openPeerId == c.peerId,
              themeState: themeState,
              onTap: () {
                context.read<DmCubit>().closeConversation();
                context.read<central.CentralDmCubit>().openConversation(
                  peerId: c.peerId,
                  peerHandle: c.peerName,
                  peerChatKey: c.peerChatPublicKey,
                  peerSigningKey: c.peerSigningPublicKey,
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // ── Server tier ──────────────────────────────────────
        _SectionHeader(
          themeState: themeState,
          icon: Icons.dns_outlined,
          label: serverName ?? 'This server',
          onAdd: serverName != null
              ? () => NewServerDmDialog.show(context)
              : null,
        ),
        const SizedBox(height: 4),
        if (serverName == null)
          _HintText(
            themeState: themeState,
            text: 'Join a server to message its members.',
          )
        else if (dmState.conversations.isEmpty)
          _HintText(
            themeState: themeState,
            text: 'No conversations on this server yet.',
          )
        else
          ...dmState.conversations.map(
            (c) => DmConversationTile(
              conversation: c,
              icon: Icons.dns_outlined,
              isSelected: dmState.openPeerId == c.peerId,
              themeState: themeState,
              onTap: () {
                context.read<central.CentralDmCubit>().closeConversation();
                context.read<DmCubit>().openConversation(
                  peerId: c.peerId,
                  peerName: c.peerName,
                  peerChatKey: c.peerChatPublicKey,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final ThemeState themeState;
  final IconData icon;
  final String label;
  final VoidCallback? onAdd;

  const _SectionHeader({
    required this.themeState,
    required this.icon,
    required this.label,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: themeState.textQuaternary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: themeState.textQuaternary,
            ),
          ),
        ),
        if (onAdd != null)
          IconButton(
            onPressed: onAdd,
            icon: Icon(Icons.add, size: 16, color: themeState.textTertiary),
            tooltip: 'New conversation',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
      ],
    );
  }
}

class _HintText extends StatelessWidget {
  final ThemeState themeState;
  final String text;

  const _HintText({required this.themeState, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: themeState.textQuaternary),
      ),
    );
  }
}
