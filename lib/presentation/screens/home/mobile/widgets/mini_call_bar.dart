import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/calls/call_return_bar.dart';
import '../mobile_shell_scope.dart';

/// The call you are in, kept one tap away from every other screen on a phone.
///
/// A desktop keeps the call in a pane beside whatever you are reading, so it
/// has nothing like this. A phone pushes the call as a page and lets you leave
/// the page without leaving the call — which would leave you in a call you
/// can no longer see, unable to mute. So this sits over the list and above
/// every composer: the channel, how long, your mic, and Leave, with the rest
/// of the bar taking you back in.
///
/// Draws nothing outside the phone shell, outside a call, or while the call
/// page itself is on top.
class MiniCallBar extends StatelessWidget {
  const MiniCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = MobileShellScope.maybeOf(context);
    if (shell == null || shell.callOnTop) return const SizedBox.shrink();

    return BlocBuilder<LiveKitCubit, LiveKitState>(
      buildWhen: (a, b) =>
          a.connectionState != b.connectionState ||
          a.currentChannelId != b.currentChannelId ||
          a.dmCall != b.dmCall ||
          a.isMicOn != b.isMicOn ||
          a.connectedAt != b.connectedAt,
      builder: (context, call) {
        final channelId = call.currentChannelId;
        // Asked whatever the call is, so the lookup is the same on every
        // build; a DM call simply does not use the answer.
        final channelName = context.select<ServerCubit, String>(
          (c) =>
              c.state.selectedServer?.channels
                  .where((ch) => ch.id == channelId)
                  .map((ch) => ch.name)
                  .firstOrNull ??
              'Voice',
        );
        final dm = call.dmCall;
        if (!call.inCall ||
            call.connectionState == LiveKitConnectionState.disconnected) {
          return const SizedBox.shrink();
        }
        return CallReturnBar(
          channelName: dm?.peerName ?? channelName,
          failed: call.connectionState == LiveKitConnectionState.error,
          connectedAt: call.connectedAt,
          micOn: call.isMicOn,
          onOpen: shell.openCall,
          onLeave: dm != null
              ? () => context.read<DmCallCubit>().hangUp()
              : () => context.read<LiveKitCubit>().disconnect(),
        );
      },
    );
  }
}
