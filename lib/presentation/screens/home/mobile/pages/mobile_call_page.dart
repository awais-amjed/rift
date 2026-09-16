import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../chat/widgets/header_pane_buttons.dart';
import '../../participants_grid/participants_grid.dart';

/// The call, standing on its own.
///
/// The grid and its floating controls are the desktop's. Once the room is up
/// the strip across its top carries the way back to the list (see
/// `ContextStrip`); before that — connecting, or a join that failed — there is
/// no strip, so the way back is put here instead. Going back never leaves the
/// call.
class MobileCallPage extends StatelessWidget {
  const MobileCallPage({super.key});

  @override
  Widget build(BuildContext context) {
    final connected = context.select<LiveKitCubit, bool>(
      (c) =>
          c.state.connectionState == LiveKitConnectionState.connected &&
          c.state.room != null,
    );
    if (connected) return const ParticipantsGrid();
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: HeaderBackButton(),
          ),
        ),
        Expanded(child: ParticipantsGrid()),
      ],
    );
  }
}
