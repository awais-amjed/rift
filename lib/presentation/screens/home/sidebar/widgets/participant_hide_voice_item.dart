import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';

/// "Hide my voice from them": the one item on a participant's menu that is
/// about what *they* hear, not what you do. The call server stops sending
/// them your microphone, in every call, until you take it back — see
/// `VoicePrivacy`.
class ParticipantHideVoiceItem extends StatelessWidget {
  final String targetUserId;

  const ParticipantHideVoiceItem({super.key, required this.targetUserId});

  @override
  Widget build(BuildContext context) {
    final hidden = context.select(
      (AppCubit c) => c.state.voiceHiddenFrom.contains(targetUserId),
    );
    return ContextMenuItem(
      icon: Icons.voice_over_off_rounded,
      label: hidden ? 'Stop hiding my voice' : 'Hide my voice from them',
      isDangerous: hidden,
      onTap: () => context.read<LiveKitCubit>().setVoiceHiddenFrom(
        targetUserId,
        !hidden,
      ),
    );
  }
}
