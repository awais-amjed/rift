import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/livekit/livekit_cubit.dart';
import '../../logic/cubits/server/server_cubit.dart';
import 'server_context_scope.dart';
import 'server_scope.dart';

/// The call's surfaces, about the call's server whichever one is selected —
/// see [ServerScope]: the grid, and the call's controls wherever they sit.
///
/// The call's server's context, which is the selected one's while the call is
/// on it, so opening another server swaps nothing under the call's video.
/// Before a call, it is about the selected server, as everything round it is.
class CallServerScope extends StatelessWidget {
  final Widget child;

  const CallServerScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final callServerId = context.select<LiveKitCubit, String?>(
      (cubit) => cubit.state.callServerId,
    );
    final selectedId = context.select<ServerCubit, String?>(
      (cubit) => cubit.state.selectedServer?.id,
    );
    final serverId = callServerId ?? selectedId;
    if (serverId == null) return child;
    return ServerContextScope(serverId: serverId, child: child);
  }
}
