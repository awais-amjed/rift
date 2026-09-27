import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/dm_call.dart';
import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';

/// Put the conversation [call] belongs to on screen, on its own server —
/// which is where a desktop shows the call, above the messages.
///
/// Selecting the server first when the call rang on another one, and waiting
/// for the DM list to move over before opening the person: opened any sooner,
/// the switch finishing behind it would close the conversation again.
Future<void> openCallConversation(
  BuildContext context, {
  required String serverId,
  required DmCall call,
}) async {
  final servers = context.read<ServerCubit>();
  final dms = context.read<DmCubit>();
  final central = context.read<CentralDmCubit>();
  final app = context.read<AppCubit>();

  final server = servers.state.servers
      .where((s) => s.id == serverId)
      .firstOrNull;
  if (server == null) return;
  if (servers.state.selectedServer?.id != serverId) {
    servers.selectServer(server);
    await dms.readyFor(serverId);
  }
  // Only one DM surface is open at a time.
  central.closeConversation();
  await dms.openConversation(
    peerId: call.peerId,
    peerName: call.peerName,
    peerChatKey: call.peerChatPublicKey,
  );
  app.setSurface(HomeSurface.serverDms);
}
