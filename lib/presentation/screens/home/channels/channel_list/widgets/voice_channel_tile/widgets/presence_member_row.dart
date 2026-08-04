import 'package:flutter/material.dart';

import '../../../../../../../../data/classes/participant_setting.dart';
import '../../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../common/context_menu_region.dart';
import '../../../../../../../common/squircle_avatar.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/custom_colors.dart';
import '../../../../../sidebar/widgets/participant_context_menu.dart';

/// A member of a voice channel you're not in — rendered from Realtime
/// presence, so we only have their name (no live mic/speaking state).
///
/// Right-clicking still opens the participant menu: local mute and volume are
/// stored per user id and applied the next time you share a voice channel, so
/// they can be set before ever meeting them in a call. The menu keys off the
/// user id since there is no LiveKit identity for someone we aren't connected
/// with. [setting] shows any stored preference so the row reflects it.
class PresenceMemberRow extends StatelessWidget {
  final PresenceUser user;
  final ThemeState themeState;
  final ParticipantSetting? setting;

  const PresenceMemberRow({
    super.key,
    required this.user,
    required this.themeState,
    this.setting,
  });

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      contextMenu: ParticipantContextMenu(
        identity: user.userId,
        name: user.displayName,
      ),
      child: _buildRow(),
    );
  }

  Widget _buildRow() {
    final isMuted = setting?.muted ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Row(
        spacing: 8,
        children: [
          SquircleAvatar(name: user.displayName, seed: user.userId, size: 22),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.secondary.copyWith(
                fontWeight: FontWeight.w500,
                color: themeState.textSecondary,
              ),
            ),
          ),
          // Locally muted, even though they're in another channel — otherwise
          // the mute is invisible until you next join them.
          if (isMuted)
            const Icon(
              Icons.volume_off_rounded,
              size: 13,
              color: CustomColors.error,
            ),
        ],
      ),
    );
  }
}
