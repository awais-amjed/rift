import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/connection_failure.dart';
import '../pane_toggles/pane_corner_toggles.dart';
import 'widgets/connecting_view.dart';
import 'widgets/dm_ringing_view.dart';
import 'widgets/error_view.dart';
import 'widgets/no_channel_view.dart';
import 'widgets/room_view.dart';

/// Main video/audio area — renders the LiveKit room state. The voice
/// connect/disconnect listener lives in MainContent so it survives the
/// chat/voice pane switch.
class ParticipantsGrid extends StatelessWidget {
  /// Drawn inside another pane — a DM conversation's call, above its
  /// messages — rather than as the whole centre of the window. The pane
  /// around it has its own header and its own ways to show the side panels,
  /// and a stage that went full-bleed would take the conversation with it.
  final bool embedded;

  const ParticipantsGrid({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      // One field of thirty, and everything below it is the whole call view.
      // Without this a hover flag or a local mute rebuilt the grid, the tiles
      // and every video surface in it.
      buildWhen: (previous, current) =>
          previous.selectedChannelId != current.selectedChannelId,
      builder: (context, appState) {
        return BlocBuilder<LiveKitCubit, LiveKitState>(
          // Only what picks the view. Every speaking change emits a new state,
          // and [RoomView] listens for the participants itself.
          buildWhen: (prev, curr) =>
              prev.connectionState != curr.connectionState ||
              prev.failure != curr.failure ||
              prev.room != curr.room ||
              prev.dmCall != curr.dmCall,
          builder: (context, livekitState) {
            // Asked on every build, so the lookup is registered the same way
            // whatever is showing; only a DM call uses the answer.
            final ringingOut = context.select<DmCallCubit, bool>(
              (c) => c.state.isRingingOut,
            );
            // A DM call selects no channel: the call is the thing selected.
            if (appState.selectedChannelId == null &&
                livekitState.dmCall == null) {
              return _headerless(const NoChannelView.nothingSelected());
            }
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

            // Our own DM call, still ringing at the other end: who we are
            // calling, rather than a room with only us in it.
            final dm = livekitState.dmCall;
            if (dm != null && ringingOut) {
              return _headerless(DmRingingView(place: dm));
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
                    onLeave: () => dm != null
                        ? context.read<DmCallCubit>().hangUp()
                        : context.read<LiveKitCubit>().disconnect(),
                  ),
                );
              case LiveKitConnectionState.connected:
                if (livekitState.room == null) {
                  return _headerless(const ConnectingView());
                }
                return RoomView(
                  room: livekitState.room!,
                  embedded: embedded,
                );
            }
          },
        );
      },
    );
  }

  /// Every state but the call itself, which has a header of its own to put
  /// the show buttons in. Embedded, the pane around it has them already.
  Widget _headerless(Widget view) =>
      embedded ? view : PaneCornerToggles.over(view);
}
