import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../mobile/mobile_shell_scope.dart';
import 'open_call_conversation.dart';

/// Puts [call] in the centre: a DM call's conversation, or a channel's stage
/// on its own server, with any chat over it closed. On a phone, the call's
/// page, as the call bar does.
///
/// What the dock's call and a stream floating over a chat both do when
/// pressed.
void showTheCall(BuildContext context, LiveKitState call) {
  final shell = MobileShellScope.maybeOf(context);
  if (shell != null) {
    shell.openCall();
    return;
  }
  final dm = call.dmCall;
  if (dm != null) {
    final row = context.read<DmCallCubit>().state.active?.call;
    if (row == null) return;
    unawaited(openCallConversation(context, serverId: dm.serverId, call: row));
    return;
  }
  final channelId = call.currentChannelId;
  final servers = context.read<ServerCubit>();
  final home = servers.state.servers
      .where((s) => s.channels.any((c) => c.id == channelId))
      .firstOrNull;
  if (home != null && servers.state.selectedServerId != home.id) {
    servers.selectServer(home);
  }
  context.read<AppCubit>().setSurface(HomeSurface.server);
  unawaited(context.read<ChannelChatCubit>().closeChannel());
}
