import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../controls/control_bar.dart';
import 'participant_grid.dart';
import 'waiting_view.dart';

/// Room is connected — shows participant tiles + control bar.
class RoomView extends StatelessWidget {
  final Room room;

  const RoomView({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Get participants directly from the cubit state
        final participants = livekitState.participants;

        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            return Stack(
              children: [
                participants.isEmpty
                    ? const WaitingView()
                    : ParticipantGrid(
                        participants: participants,
                        participantSettings: appState.participantSettings,
                      ),
                const ControlBar(),
              ],
            );
          },
        );
      },
    );
  }
}
