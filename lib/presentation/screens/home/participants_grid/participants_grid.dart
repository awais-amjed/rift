import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import 'widgets/connecting_view.dart';
import 'widgets/error_view.dart';
import 'widgets/no_channel_view.dart';
import 'widgets/room_view.dart';

/// Main video/audio area. Connects to LiveKit and renders participant tiles.
class ParticipantsGrid extends StatefulWidget {
  const ParticipantsGrid({super.key});

  @override
  State<ParticipantsGrid> createState() => _ParticipantsGridState();
}

class _ParticipantsGridState extends State<ParticipantsGrid> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      listener: (context, appState) {
        final livekitCubit = context.read<LiveKitCubit>();
        final serverState = context.read<ServerCubit>().state;
        final server = serverState.selectedServer;

        if (appState.selectedChannelId == null) {
          livekitCubit.disconnect();
          return;
        }

        if (server == null) return;
        if (server.user == null) return;
        if (server.livekitUrl == null) return;

        livekitCubit.connectToChannel(
          channelId: appState.selectedChannelId!,
          micEnabled: appState.audioEnabled,
          cameraEnabled: appState.videoEnabled,
        );
      },
      child: BlocBuilder<AppCubit, AppState>(
        builder: (context, appState) {
          if (appState.selectedChannelId == null) {
            return const NoChannelView();
          }

          return BlocBuilder<LiveKitCubit, LiveKitState>(
            builder: (context, livekitState) {
              final server = context.read<ServerCubit>().state.selectedServer;

              if (server?.user == null) {
                return const ErrorView(
                  error: 'Please create a user account to join voice channels',
                );
              }

              if (server?.livekitUrl == null) {
                return const ErrorView(
                  error: 'This server has no LiveKit URL configured',
                );
              }

              switch (livekitState.connectionState) {
                case LiveKitConnectionState.disconnected:
                  return const NoChannelView();
                case LiveKitConnectionState.connecting:
                  return const ConnectingView();
                case LiveKitConnectionState.error:
                  return ErrorView(
                    error: livekitState.error ?? 'Unknown error',
                  );
                case LiveKitConnectionState.connected:
                  if (livekitState.room == null) {
                    return const ConnectingView();
                  }
                  return RoomView(room: livekitState.room!);
              }
            },
          );
        },
      ),
    );
  }
}
