import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/participant_identity.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/share_audio_controls.dart';

/// What a viewer can do about the sound of somebody's screen share: turn it
/// down, or off.
///
/// The stream's own menu rather than its owner's, which is what this tile used
/// to open — so the only volume on offer was their voice, and a game too loud
/// to talk over could not be turned down without them. Their menu is on their
/// own tile.
class StreamContextMenu extends StatelessWidget {
  /// The stream's LiveKit identity. On a phone that is the owner's own
  /// connection, which is why the key is asked for as screen audio.
  final String identity;

  final String ownerName;

  const StreamContextMenu({
    super.key,
    required this.identity,
    required this.ownerName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return ContextMenuPanel(
      heading: 'Stream',
      subheading: ownerName,
      leading: Icon(
        Icons.screen_share_outlined,
        size: K.iconButton,
        color: theme.accentBright,
      ),
      children: [
        Divider(height: 9, color: theme.borderPrimary),
        ShareAudioControls(
          settingsKey: ParticipantIdentity.settingsKeyOf(
            identity,
            screenAudio: true,
          ),
          noun: 'stream sound',
        ),
      ],
    );
  }
}
