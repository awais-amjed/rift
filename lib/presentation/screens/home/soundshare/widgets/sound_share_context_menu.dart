import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../theme/theme_context.dart';
import '../../sidebar/widgets/participant_volume_control.dart';

/// What a listener can do about somebody else's shared sound: turn it off, or
/// turn it down.
///
/// Both are stored against the share rather than its owner — muting the music
/// somebody has on is not muting them, and the two would otherwise be the same
/// switch. See [LiveKitCubit.setSoundShareMute].
class SoundShareContextMenu extends StatelessWidget {
  /// The share's LiveKit identity, not its owner's.
  final String identity;

  /// Whose share it is, for the heading.
  final String ownerName;

  /// Your own share reaches you as any other connection would; there is
  /// nothing to turn down, because it was never subscribed to.
  final bool isOwn;

  final VoidCallback? onStopSharing;

  const SoundShareContextMenu({
    super.key,
    required this.identity,
    required this.ownerName,
    required this.isOwn,
    this.onStopSharing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final key = ParticipantIdentity.soundShareSettingsKey(identity);
    final setting = context.watch<AppCubit>().state.participantSettings[key];
    final isMuted = setting?.muted ?? false;
    final volume = setting?.volume ?? 1.0;

    return ContextMenuPanel(
      heading: 'Shared sound',
      subheading: isOwn ? 'You are sharing' : '$ownerName’s sound',
      leading: Icon(
        Icons.graphic_eq_rounded,
        size: 18,
        color: theme.accentBright,
      ),
      children: [
        Divider(height: 9, color: theme.borderPrimary),
        if (isOwn)
          ContextMenuItem(
            icon: Icons.stop_circle_outlined,
            label: 'Stop sharing',
            isDangerous: true,
            onTap: () => onStopSharing?.call(),
          )
        else ...[
          ContextMenuItem(
            icon: isMuted ? Icons.volume_off : Icons.volume_up,
            label: isMuted ? 'Unmute sound' : 'Mute sound',
            isDangerous: isMuted,
            onTap: () => context.read<LiveKitCubit>().setSoundShareMute(
              identity,
              !isMuted,
            ),
          ),
          Divider(height: 9, color: theme.borderPrimary),
          ParticipantVolumeControl(
            target: identity,
            isMuted: isMuted,
            volume: volume,
            onChanged: (value) => context
                .read<LiveKitCubit>()
                .setSoundShareVolume(identity, value),
          ),
        ],
      ],
    );
  }
}
