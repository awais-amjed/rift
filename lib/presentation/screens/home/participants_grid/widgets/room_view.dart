import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../controls/context_strip.dart';
import '../../controls/control_bar.dart';
import 'participant_grid_layout.dart';
import 'waiting_view.dart';

/// Room is connected — shows participant tiles + control bar.
class RoomView extends StatefulWidget {
  final Room room;

  const RoomView({super.key, required this.room});

  @override
  State<RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<RoomView> {
  final _controlBarKey = GlobalKey<ControlBarState>();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Get participants directly from the cubit state
        final participants = livekitState.participants;

        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerHover: (_) => _controlBarKey.currentState?.onActivity(),
              onPointerMove: (_) => _controlBarKey.currentState?.onActivity(),
              child: Stack(
                children: [
                  Column(
                    children: [
                      const ContextStrip(),
                      Expanded(
                        child: participants.isEmpty
                            ? const WaitingView()
                            : ParticipantGridLayout(
                                participants: participants,
                                participantSettings:
                                    appState.participantSettings,
                              ),
                      ),
                    ],
                  ),
                  ControlBar(key: _controlBarKey),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
