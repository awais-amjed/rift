import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/confirm_dialog.dart';

/// Whether to go ahead with joining [target], asking first when that would
/// leave another call.
///
/// Answers true straight away when there is no call to leave, when [target]
/// is the call already joined, or when the user has said not to ask — which
/// "Don't ask again" here does, and Settings → Voice & audio undoes.
///
/// For clicks only. Dragging yourself onto a channel is already deliberate,
/// and a moderator moving you is not yours to confirm.
Future<bool> confirmVoiceSwitch(BuildContext context, Channel target) async {
  final appCubit = context.read<AppCubit>();
  final current = appCubit.state.selectedChannelId;
  if (current == null || current == target.id) return true;
  if (!appCubit.state.askBeforeVoiceSwitch) return true;

  final answer = await showConfirmDialogWithOptOut(
    context: context,
    title: 'Switch voice channel?',
    message:
        'You will leave ${_nameOf(context, current)} and join '
        '${target.name}.',
    confirmLabel: 'Switch',
    icon: Icons.swap_horiz_rounded,
  );
  if (answer.confirmed && answer.dontAskAgain) {
    appCubit.setAskBeforeVoiceSwitch(false);
  }
  return answer.confirmed;
}

/// The call being left, by name when this server has it. A call on another
/// server is not in the selected one's channel list.
String _nameOf(BuildContext context, String channelId) {
  final channels =
      context.read<ServerCubit>().state.selectedServer?.channels ?? const [];
  for (final c in channels) {
    if (c.id == channelId) return c.name;
  }
  return 'your current call';
}
