import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';

/// "Mute everyone else for me": the call goes quiet but for this one person,
/// on this device, until you take it back or the call ends — see
/// `LiveKitState.listeningOnlyTo`. Choosing it on somebody else moves it to
/// them.
class ParticipantHearOnlyItem extends StatelessWidget {
  final String targetUserId;

  const ParticipantHearOnlyItem({super.key, required this.targetUserId});

  @override
  Widget build(BuildContext context) {
    final only = context.select(
      (LiveKitCubit c) => c.state.listeningOnlyTo == targetUserId,
    );
    return ContextMenuItem(
      icon: Icons.hearing_rounded,
      label: only ? 'Unmute everyone else' : 'Mute everyone else for me',
      isDangerous: only,
      onTap: () =>
          context.read<LiveKitCubit>().setListeningOnlyTo(targetUserId, !only),
    );
  }
}

/// "Hide my voice from others": only this person receives your
/// microphone, for this call — see `LiveKitState.voiceOnlyFor`. The call
/// server enforces it, as it does "Hide my voice from them".
class ParticipantVoiceOnlyItem extends StatelessWidget {
  final String targetUserId;

  const ParticipantVoiceOnlyItem({super.key, required this.targetUserId});

  @override
  Widget build(BuildContext context) {
    final only = context.select(
      (LiveKitCubit c) => c.state.voiceOnlyFor == targetUserId,
    );
    return ContextMenuItem(
      icon: Icons.record_voice_over_rounded,
      label: only ? 'Let others hear me' : 'Hide my voice from others',
      isDangerous: only,
      onTap: () =>
          context.read<LiveKitCubit>().setVoiceOnlyFor(targetUserId, !only),
    );
  }
}
