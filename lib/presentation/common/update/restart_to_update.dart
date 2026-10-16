import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/call_to_resume.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/cubits/update/update_cubit.dart';
import '../confirm_dialog.dart';

/// Restarts Rift into the downloaded update — after asking, when that would
/// leave a call. A channel's call is rejoined when the new version starts; a
/// direct call is not, since it rang somebody and has nothing to go back to.
Future<void> restartToUpdate(BuildContext context) async {
  final updates = context.read<UpdateCubit>();
  final livekit = context.read<LiveKitCubit>();
  final channelId = livekit.state.currentChannelId;
  if (livekit.state.inCall) {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restart to update?',
      message: channelId != null
          ? 'You leave the call for a few seconds. Rift opens again by '
                'itself and puts you back in.'
          : 'Restarting leaves the call. Rift opens again by itself in a few '
                'seconds.',
      confirmLabel: 'Restart',
      icon: Icons.system_update_alt_rounded,
    );
    if (!confirmed) return;
  }
  // Read after the question: the call may have ended while it was open.
  final call = livekit.state;
  await updates.restartToUpdate(
    call: call.currentChannelId == null
        ? null
        : CallToResume(
            channelId: call.currentChannelId!,
            deafened: call.isDeafened,
            savedAt: DateTime.now(),
          ),
  );
}
