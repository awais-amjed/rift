import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/share_audio_controls.dart';

/// What a viewer can do about a screen share: turn its sound down or off, or
/// stop watching just this one.
///
/// The stream's own menu rather than its owner's, which is what this tile used
/// to open — so the only volume on offer was their voice, and a game too loud
/// to talk over could not be turned down without them. Their menu is on their
/// own tile.
///
/// Your own stream opens it too, under a key of its own whose sound starts
/// off ([ParticipantIdentity.ownStreamSettingsKey]).
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
    final livekit = context.read<LiveKitCubit>();
    final localIdentity = livekit.state.room?.localParticipant?.identity;
    final watching = context.select<LiveKitCubit, bool>(
      (cubit) => cubit.state.subscribedScreenshares.contains(identity),
    );
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
            localIdentity: localIdentity,
          ),
          noun: 'stream sound',
        ),
        // The call bar's Stop watching puts every stream away; with two
        // open, this is how to close one.
        if (watching) ...[
          Divider(height: 9, color: theme.borderPrimary),
          ContextMenuItem(
            icon: Icons.cancel_presentation,
            label: 'Stop watching',
            onTap: () {
              ContextMenuScope.of(context)?.call();
              livekit.unsubscribeFromScreenshare(identity);
            },
          ),
        ],
      ],
    );
  }
}
