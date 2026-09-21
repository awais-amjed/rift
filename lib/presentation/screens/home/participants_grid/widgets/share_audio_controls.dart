import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../sidebar/widgets/participant_volume_control.dart';

/// How loud somebody's shared sound is here, then whether it plays at all —
/// the same order as a person's menu.
///
/// Stored under [settingsKey], apart from their voice: turning a game or the
/// music down is not turning its owner down. Stored per person, so it holds
/// the next time they share.
class ShareAudioControls extends StatelessWidget {
  final String settingsKey;

  /// What the mute says it silences — "sound", "stream sound".
  final String noun;

  const ShareAudioControls({
    super.key,
    required this.settingsKey,
    required this.noun,
  });

  @override
  Widget build(BuildContext context) {
    final setting = context.select<AppCubit, ({bool muted, double volume})>((
      cubit,
    ) {
      final s = cubit.state.participantSettings[settingsKey];
      return (muted: s?.muted ?? false, volume: s?.volume ?? 1.0);
    });
    final livekit = context.read<LiveKitCubit>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParticipantVolumeControl(
          target: settingsKey,
          isMuted: setting.muted,
          volume: setting.volume,
          onChanged: (value) => livekit.setVolumeFor(settingsKey, value),
        ),
        ContextMenuItem(
          icon: setting.muted ? Icons.volume_off : Icons.volume_up,
          label: setting.muted ? 'Unmute $noun' : 'Mute $noun',
          isDangerous: setting.muted,
          onTap: () => livekit.setMuteFor(settingsKey, !setting.muted),
        ),
      ],
    );
  }
}
