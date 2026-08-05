import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import 'widgets/connecting_view.dart';
import 'widgets/error_view.dart';
import 'widgets/no_channel_view.dart';
import 'widgets/room_view.dart';

/// Main video/audio area — renders the LiveKit room state. The voice
/// connect/disconnect listener lives in MainContent so it survives the
/// chat/voice pane switch.
class ParticipantsGrid extends StatelessWidget {
  const ParticipantsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
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
                // Only this branch gets the actions: the two checks above are
                // preconditions of the screen, not of the connection, so
                // nothing about retrying them would come out differently.
                return ErrorView(
                  error: livekitState.error ?? 'Unknown error',
                  onRetry: () => context.read<LiveKitCubit>().retryConnection(),
                  onLeave: () => context.read<LiveKitCubit>().disconnect(),
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
    );
  }
}
