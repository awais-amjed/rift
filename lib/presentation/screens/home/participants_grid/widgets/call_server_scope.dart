import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/call_members_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../common/server_scope.dart';

/// The call's surfaces, about the call's server whichever one is selected —
/// see [ServerScope].
///
/// The selected server's roster while the call is on it, which has usually
/// loaded by the time anyone joins; the call's own ([CallMembersCubit]) while
/// another server is open. Always the same two widgets around [child], with
/// only their values moving, so opening another server swaps whose faces the
/// tiles read without rebuilding the call's video under them.
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
    final elsewhere = callServerId != null && callServerId != selectedId;
    return ServerScope(
      serverId: callServerId,
      child: BlocProvider<ServerMembersCubit>.value(
        value: elsewhere
            ? context.read<CallMembersCubit>()
            : context.read<ServerMembersCubit>(),
        child: child,
      ),
    );
  }
}
