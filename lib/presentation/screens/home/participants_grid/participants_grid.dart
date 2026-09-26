import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/connection_failure.dart';
import '../pane_toggles/pane_corner_toggles.dart';
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
      // One field of thirty, and everything below it is the whole call view.
      // Without this a hover flag or a local mute rebuilt the grid, the tiles
      // and every video surface in it.
      buildWhen: (previous, current) =>
          previous.selectedChannelId != current.selectedChannelId,
      builder: (context, appState) {
        if (appState.selectedChannelId == null) {
          return _headerless(const NoChannelView.nothingSelected());
        }

        return BlocBuilder<LiveKitCubit, LiveKitState>(
          // Only what picks the view. Every speaking change emits a new state,
          // and [RoomView] listens for the participants itself.
          buildWhen: (prev, curr) =>
              prev.connectionState != curr.connectionState ||
              prev.failure != curr.failure ||
              prev.room != curr.room,
          builder: (context, livekitState) {
            final server = context.read<ServerCubit>().state.selectedServer;

            if (server?.user == null) {
              return _headerless(
                const ErrorView(
                  failure: ConnectionFailure(
                    title: 'No account on this server',
                    message:
                        'Create a user account on this server before joining a '
                        'voice channel.',
                    canRetry: false,
                  ),
                ),
              );
            }

            if (server?.livekitUrl == null) {
              return _headerless(
                const ErrorView(failure: ConnectionFailure.noLiveKitUrl()),
              );
            }

            switch (livekitState.connectionState) {
              case LiveKitConnectionState.disconnected:
                return _headerless(const NoChannelView.notInCall());
              case LiveKitConnectionState.connecting:
                return _headerless(const ConnectingView());
              case LiveKitConnectionState.error:
                final failure =
                    livekitState.failure ?? const ConnectionFailure.unknown();
                return _headerless(
                  ErrorView(
                    failure: failure,
                    // Leaving is always offered; retrying only where it could
                    // change the outcome. A misconfigured server would fail the
                    // same way forever, and a button that cannot work is worse
                    // than no button.
                    onRetry: failure.canRetry
                        ? () => context.read<LiveKitCubit>().retryConnection()
                        : null,
                    onLeave: () => context.read<LiveKitCubit>().disconnect(),
                  ),
                );
              case LiveKitConnectionState.connected:
                if (livekitState.room == null) {
                  return _headerless(const ConnectingView());
                }
                return RoomView(room: livekitState.room!);
            }
          },
        );
      },
    );
  }

  /// Every state but the call itself, which has a header of its own to put
  /// the show buttons in.
  static Widget _headerless(Widget view) => PaneCornerToggles.over(view);
}
