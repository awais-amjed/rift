import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import '../../../data/enums/home_surface.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../logic/cubits/dm/dm_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../../logic/services/host_platform.dart';
import '../../../logic/services/notification_ids.dart';
import '../../../logic/services/notification_service.dart';
import 'dms/open_central_conversation.dart';

/// Takes a press on a message notification to the conversation it is about.
///
/// A notification is only ever posted while the window is out of sight, so
/// the press is first of all a request to come back: on a desktop the window
/// is shown and brought forward even when there is nothing to open. Before
/// this, a press did nothing at all — the window stayed minimised or in the
/// tray, and the person had to find it themselves.
class ConversationNotificationRouter extends StatefulWidget {
  final Widget child;

  const ConversationNotificationRouter({super.key, required this.child});

  @override
  State<ConversationNotificationRouter> createState() =>
      _ConversationNotificationRouterState();
}

class _ConversationNotificationRouterState
    extends State<ConversationNotificationRouter> {
  StreamSubscription<ConversationNotificationPayload?>? _presses;

  @override
  void initState() {
    super.initState();
    _presses = NotificationService.instance.messagePresses.listen(_handle);
    final early = NotificationService.instance.takeUnclaimedPress();
    if (early != null) unawaited(_handleOnceUnlocked(early.target));
  }

  /// A press that started Rift (Windows starts it to deliver one) lands
  /// before the vault has opened, and a channel opened then fails as locked:
  /// its key cannot be unwrapped without the seed. So that one waits for it.
  Future<void> _handleOnceUnlocked(
    ConversationNotificationPayload? target,
  ) async {
    final vault = context.read<VaultCubit>();
    if (vault.state.masterSeed == null) {
      await vault.stream.firstWhere((s) => s.masterSeed != null);
    }
    if (mounted) await _handle(target);
  }

  @override
  void dispose() {
    unawaited(_presses?.cancel());
    super.dispose();
  }

  Future<void> _handle(ConversationNotificationPayload? target) async {
    if (HostPlatform.isDesktop) {
      await windowManager.show();
      await windowManager.focus();
    }
    if (target == null || !mounted) return;
    if (target.isCentralDm) {
      _openCentralDm(target.targetId);
    } else {
      await _openOnServer(target);
    }
  }

  Future<void> _openOnServer(ConversationNotificationPayload target) async {
    final servers = context.read<ServerCubit>();
    final dms = context.read<DmCubit>();
    final app = context.read<AppCubit>();
    final chat = context.read<ChannelChatCubit>();

    final server = servers.state.servers
        .where((s) => s.id == target.serverId)
        .firstOrNull;
    if (server == null) return;
    if (servers.state.selectedServer?.id != server.id) {
      servers.selectServer(server);
      // The chat closes whatever it had open when it hears of the switch;
      // opening before it has heard would be closed straight away.
      if (target.isChannel) await Future<void>.delayed(Duration.zero);
    }
    if (!mounted) return;

    if (target.isChannel) {
      app.setSurface(HomeSurface.server);
      unawaited(chat.openChannel(target.targetId));
      return;
    }

    // A DM: once the list has moved to this server, open the person from it,
    // which has the key the conversation needs.
    await dms.readyFor(server.id);
    if (!mounted) return;
    final conversation = dms.state.conversations
        .where((c) => c.peerId == target.targetId)
        .firstOrNull;
    context.read<CentralDmCubit>().closeConversation();
    if (conversation != null) {
      await dms.openConversation(
        peerId: conversation.peerId,
        peerName: conversation.peerName,
        peerChatKey: conversation.peerChatPublicKey,
      );
    }
    app.setSurface(HomeSurface.serverDms);
  }

  void _openCentralDm(String peerId) {
    final conversation = context
        .read<CentralDmCubit>()
        .state
        .conversations
        .where((c) => c.peerId == peerId)
        .firstOrNull;
    context.read<AppCubit>().setSurface(HomeSurface.centralDms);
    if (conversation != null) openCentralConversation(context, conversation);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
