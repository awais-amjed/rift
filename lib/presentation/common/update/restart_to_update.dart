import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/cubits/update/update_cubit.dart';
import '../confirm_dialog.dart';

/// Restarts Rift into the downloaded update — after asking, when that would
/// leave a call.
Future<void> restartToUpdate(BuildContext context) async {
  final updates = context.read<UpdateCubit>();
  if (context.read<LiveKitCubit>().state.inCall) {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Restart to update?',
      message:
          'Restarting leaves the call. Rift opens again by itself in a few '
          'seconds.',
      confirmLabel: 'Restart',
      icon: Icons.system_update_alt_rounded,
    );
    if (!confirmed) return;
  }
  await updates.restartToUpdate();
}
