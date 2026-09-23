import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../common/quiet_danger_button.dart';
import '../../../../theme/theme_context.dart';

/// The mute / deafen / ban half of a member's management panel.
///
/// Split out because it answers to different permissions than the half above
/// it: muting and deafening are a moderator's, and banning is an admin's, and
/// the panel was carrying both sets of conditions inline.
class MemberModerationRow extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canModerate;
  final bool canBan;

  /// Whether anything sits above this in the panel, and so whether it needs a
  /// rule to sit under.
  final bool dividerAbove;

  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;
  final VoidCallback onToggleBan;

  const MemberModerationRow({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canModerate,
    required this.canBan,
    required this.dividerAbove,
    required this.onModerate,
    required this.onToggleBan,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      children: [
        // An admin is nobody's moderation target — `moderate_user` raises
        // `cannot_moderate_admin` for all three of these, whoever asks,
        // the owner included. Offered anyway, muting one took a confirm
        // dialog and a round trip to say so. Ban already knew; mute and
        // deafen did not.
        if (canModerate && !member.permissions.isServerAdmin) ...[
          if (dividerAbove) Divider(height: 1, color: themeState.borderPrimary),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: QuietDangerButton(
                    icon: member.isMuted ? Icons.mic : Icons.mic_off,
                    label: member.isMuted ? 'Unmute' : 'Server mute',
                    isDangerous: !member.isMuted,

                    onTap: isBusy
                        ? null
                        : () => onModerate(muted: !member.isMuted),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: QuietDangerButton(
                    icon: member.isDeafened ? Icons.headset : Icons.headset_off,
                    label: member.isDeafened ? 'Undeafen' : 'Server deafen',
                    isDangerous: !member.isDeafened,

                    onTap: isBusy
                        ? null
                        : () => onModerate(deafened: !member.isDeafened),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Admin-only, matching `moderate_user`'s own `app.is_admin()`,
        // and never against another admin, which it also refuses —
        // removing that standing is a permission change, and the roles
        // dialog is where that happens.
        if (canBan && !member.permissions.isServerAdmin) ...[
          Divider(height: 1, color: themeState.borderPrimary),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: QuietDangerButton(
              icon: member.isBanned
                  ? Icons.lock_open_rounded
                  : Icons.gavel_rounded,
              label: member.isBanned ? 'Lift ban' : 'Ban from server',
              isDangerous: !member.isBanned,

              onTap: isBusy ? null : onToggleBan,
            ),
          ),
        ],
      ],
    );
  }
}
