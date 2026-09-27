import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/calls/call_return_bar.dart';
import 'open_call_conversation.dart';

/// A desktop's way back to a DM call, above the user dock, while the
/// conversation it is drawn in is not on screen.
///
/// A channel call is a row in the sidebar you can click; a DM call lives in
/// one conversation, and walking away from that conversation would otherwise
/// leave you talking to somebody with no picture of them and no way to hang
/// up but the dock.
class DmCallSidebarBar extends StatelessWidget {
  const DmCallSidebarBar({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<LiveKitCubit>().state;
    final dm = call.dmCall;
    final surface = context.select<AppCubit, HomeSurface>(
      (c) => c.state.surface,
    );
    final openPeer = context.select<DmCubit, String?>(
      (c) => c.state.openPeerId,
    );
    final serverId = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServer?.id,
    );
    final active = context.select<DmCallCubit, ActiveDmCall?>(
      (c) => c.state.active,
    );
    if (dm == null ||
        call.connectionState == LiveKitConnectionState.disconnected) {
      return const SizedBox.shrink();
    }
    final onScreen =
        surface == HomeSurface.serverDms &&
        openPeer == dm.peerId &&
        serverId == dm.serverId;
    if (onScreen) return const SizedBox.shrink();

    return CallReturnBar(
      channelName: dm.peerName,
      failed: call.connectionState == LiveKitConnectionState.error,
      connectedAt: call.connectedAt,
      micOn: call.isMicOn,
      onOpen: () {
        final row = active?.call;
        if (row == null) return;
        unawaited(
          openCallConversation(context, serverId: dm.serverId, call: row),
        );
      },
      onLeave: () => unawaited(context.read<DmCallCubit>().hangUp()),
      showHint: false,
    );
  }
}
