import 'package:flutter/material.dart';

import '../../../../../data/participant_identity.dart';
import '../../../../../logic/services/sound_share_label.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../theme/theme_context.dart';
import '../../participants_grid/widgets/share_audio_controls.dart';

/// What a listener can do about somebody else's shared sound: turn it off, or
/// turn it down.
///
/// Both are stored against the share rather than its owner — muting the music
/// somebody has on is not muting them, and the two would otherwise be the same
/// switch. See [ShareAudioControls].
class SoundShareContextMenu extends StatelessWidget {
  /// The share's LiveKit identity, not its owner's.
  final String identity;

  /// Whose share it is, for the heading.
  final String ownerName;

  /// The application it is playing, when it named itself — see
  /// [soundShareLabel].
  final String app;

  /// Your own share reaches you as any other connection would; there is
  /// nothing to turn down, because it was never subscribed to.
  final bool isOwn;

  final VoidCallback? onStopSharing;

  const SoundShareContextMenu({
    super.key,
    required this.identity,
    required this.ownerName,
    required this.app,
    required this.isOwn,
    this.onStopSharing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return ContextMenuPanel(
      heading: 'Shared sound',
      subheading: soundShareLabel(owner: ownerName, app: app, isOwn: isOwn),
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
        else
          ShareAudioControls(
            settingsKey: ParticipantIdentity.soundShareSettingsKey(identity),
            noun: 'sound',
          ),
      ],
    );
  }
}
