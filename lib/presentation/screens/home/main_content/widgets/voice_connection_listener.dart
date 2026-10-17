import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';

/// Joins the voice channel [AppCubit] has selected, and leaves when it is
/// cleared.
///
/// Mounted once, above whichever shell is showing, because a call outlives
/// every surface in the app: you read a chat, open a DM or — on a phone — go
/// back to the channel list, and the call carries on. It used to live in the
/// desktop's centre pane, which a phone never builds.
class VoiceConnectionListener extends StatelessWidget {
  final Widget child;

  const VoiceConnectionListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      listener: (context, appState) {
        final livekitCubit = context.read<LiveKitCubit>();
        final channelId = appState.selectedChannelId;

        if (channelId == null) {
          // A DM call clears the channel as it starts, because a device is in
          // one call at a time — that is a switch, not somebody leaving.
          if (livekitCubit.state.dmCall == null) livekitCubit.disconnect();
          return;
        }

        // The channel's own server, which is the selected one for a click but
        // not for a moderator moving you while you read another server.
        final session = context.read<SessionRepository>();
        final server =
            session.serverWithChannel(channelId) ?? session.selectedServer;
        if (server == null) return;
        if (server.user == null) return;
        if (server.livekitUrl == null) return;

        livekitCubit.connectToChannel(
          channelId: channelId,
          serverId: server.id,
          micEnabled: appState.audioEnabled,
          cameraEnabled: appState.videoEnabled,
        );
      },
      child: child,
    );
  }
}
