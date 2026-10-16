import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/auth_status.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';

/// Rejoins the call Restart to update left, once this start has unlocked —
/// see `CallToResume`.
///
/// Waits for the vault, not the first frame: the home screen is built while
/// the vault is still being read, and the call's key comes from it. Selecting
/// the channel is all it does; [VoiceConnectionListener] above it joins, the
/// same as a click on the channel.
class CallResumer extends StatefulWidget {
  final Widget child;

  const CallResumer({super.key, required this.child});

  @override
  State<CallResumer> createState() => _CallResumerState();
}

class _CallResumerState extends State<CallResumer> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _resume() async {
    if (_done || !mounted) return;
    if (context.read<VaultCubit>().state.status != AuthStatus.unlocked) return;
    _done = true;

    final app = context.read<AppCubit>();
    final call = app.takeCallToResume(DateTime.now());
    if (call == null) return;

    // Its server is whichever lists it, as the call card finds it. A channel
    // deleted, or a server left, since the restart has nothing to rejoin.
    final servers = context.read<ServerCubit>();
    final home = servers.state.servers
        .where(
          (s) => s.channels.any(
            (c) => c.id == call.channelId && c.channelType == ChannelType.voice,
          ),
        )
        .firstOrNull;
    if (home == null) {
      HelperMethods.printDebug('[Call] the call before the update is gone');
      return;
    }

    final livekit = context.read<LiveKitCubit>();
    // Somebody already picked a call in the moment since the start.
    if (livekit.state.inCall || app.state.selectedChannelId != null) return;

    HelperMethods.printDebug(
      '[Call] rejoining the call from before the update',
    );
    if (servers.state.selectedServer?.id != home.id) {
      servers.selectServer(home);
    }
    // Before the join, so no sound is heard and the mic stays shut.
    if (call.deafened && !livekit.state.isDeafened) {
      await livekit.toggleDeafen();
      if (!mounted) return;
    }
    app.setSelectedChannelId(call.channelId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VaultCubit, VaultState>(
      listenWhen: (prev, curr) =>
          prev.status != curr.status && curr.status == AuthStatus.unlocked,
      listener: (_, _) => unawaited(_resume()),
      child: widget.child,
    );
  }
}
