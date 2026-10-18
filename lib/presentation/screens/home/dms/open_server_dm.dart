import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';

/// Opens a server DM on a named server, or the selected one, closing whatever
/// DM surface was open.
///
/// A server DM belongs to a server, and the DM list follows the selection. A
/// call's tile names somebody on the call's server, which need not be the one
/// on screen, so that server is selected first and the list given time to move
/// over — opened any sooner, the switch finishing behind it would close the
/// conversation again (see `openCallConversation`).
///
/// Built from a context and used after it may be gone: a menu dismisses
/// itself before the conversation opens.
class ServerDmOpener {
  final ServerCubit _servers;
  final DmCubit _dms;
  final CentralDmCubit _central;
  final AppCubit _app;

  ServerDmOpener.of(BuildContext context)
    : _servers = context.read<ServerCubit>(),
      _dms = context.read<DmCubit>(),
      _central = context.read<CentralDmCubit>(),
      _app = context.read<AppCubit>();

  Future<void> open({
    String? serverId,
    required String peerId,
    required String peerName,
    required String? peerChatKey,
  }) async {
    if (serverId != null && _servers.state.selectedServerId != serverId) {
      final server = _servers.state.serverById(serverId);
      if (server == null) return;
      _servers.selectServer(server);
      await _dms.readyFor(serverId);
    }
    // Only one DM surface is open at a time.
    _central.closeConversation();
    await _dms.openConversation(
      peerId: peerId,
      peerName: peerName,
      peerChatKey: peerChatKey,
    );
    _app.setSurface(HomeSurface.serverDms);
  }
}
