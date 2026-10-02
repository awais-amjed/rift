import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../common/app_button_height.dart';
import '../../../../common/quiet_danger_button.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/theme_context.dart';

/// The mute / deafen / kick / ban half of a member's management panel.
///
/// Split out because it answers to different permissions than the half above
/// it: muting and deafening are a moderator's, and banning is an admin's, and
/// the panel was carrying both sets of conditions inline.
class MemberModerationRow extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canModerate;
  final bool canKick;
  final bool canBan;

  /// Whether anything sits above this in the panel, and so whether it needs a
  /// rule to sit under.
  final bool dividerAbove;

  final void Function({bool? muted, bool? deafened, bool? banned, bool kick})
  onModerate;
  final VoidCallback onToggleBan;
  final VoidCallback onKick;

  const MemberModerationRow({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canModerate,
    required this.canKick,
    required this.canBan,
    required this.dividerAbove,
    required this.onModerate,
    required this.onToggleBan,
    required this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // An admin is nobody's moderation target — `moderate_user` raises
    // `cannot_moderate_admin` for all three of these, whoever asks, the owner
    // included. Offered anyway, muting one took a confirm dialog and a round
    // trip to say so.
    if (member.permissions.isServerAdmin) return const SizedBox.shrink();
    if (!canModerate && !canKick && !canBan) return const SizedBox.shrink();
    final banned = member.isBanned && !member.isKicked;

    // Label-width and compact on a desktop: three small actions inside a
    // member's row, stretched to 44 px halves, were the loudest thing in the
    // dialog. A phone keeps the shared height, which is a thumb's.
    final height = context.layoutMode.isCompact
        ? K.controlHeight
        : K.compactControlHeight;

    return Column(
      children: [
        if (dividerAbove) Divider(height: 1, color: themeState.borderPrimary),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButtonHeight(
              height: height,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (canModerate) ...[
                    QuietDangerButton(
                      icon: member.isMuted ? Icons.mic : Icons.mic_off,
                      label: member.isMuted ? 'Unmute' : 'Server mute',
                      isDangerous: !member.isMuted,
                      onTap: isBusy
                          ? null
                          : () => onModerate(muted: !member.isMuted),
                    ),
                    QuietDangerButton(
                      icon: member.isDeafened
                          ? Icons.headset
                          : Icons.headset_off,
                      label: member.isDeafened ? 'Undeafen' : 'Server deafen',
                      isDangerous: !member.isDeafened,
                      onTap: isBusy
                          ? null
                          : () => onModerate(deafened: !member.isDeafened),
                    ),
                  ],
                  // `BAN_MEMBERS`, matching `moderate_user`'s own check.
                  // Never against an admin (above), and the server also
                  // refuses anybody who could ban back.
                  // `KICK_MEMBERS`. Not for somebody already out: kicking a
                  // banned member would make the ban liftable by an invite.
                  if (canKick && !member.isBot && !member.isBanned)
                    QuietDangerButton(
                      icon: Icons.logout_rounded,
                      label: 'Kick',
                      isDangerous: true,
                      onTap: isBusy ? null : onKick,
                    ),
                  if (canBan)
                    QuietDangerButton(
                      icon: banned
                          ? Icons.lock_open_rounded
                          : Icons.gavel_rounded,
                      label: banned ? 'Lift ban' : 'Ban from server',
                      isDangerous: !banned,
                      onTap: isBusy ? null : onToggleBan,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
