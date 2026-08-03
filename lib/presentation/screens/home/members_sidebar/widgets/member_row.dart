import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/custom_colors.dart';
import '../../sidebar/widgets/participant_context_menu.dart';

/// One member in the right-hand sidebar: avatar, name, role/state badges.
///
/// Offline members are dimmed rather than hidden, so the list is a stable
/// roster you can right-click at any time — local mute and volume are stored
/// per user and apply the next time you share a voice channel.
class MemberRow extends StatelessWidget {
  final ServerMember member;
  final ThemeState themeState;
  final bool isOnline;
  final bool isMe;
  final ParticipantSetting? setting;

  const MemberRow({
    super.key,
    required this.member,
    required this.themeState,
    required this.isOnline,
    this.isMe = false,
    this.setting,
  });

  @override
  Widget build(BuildContext context) {
    final row = _buildRow();
    // No point right-clicking yourself for a local mute.
    if (isMe) return row;
    return ContextMenuRegion(
      contextMenu: ParticipantContextMenu(
        identity: member.id,
        name: member.displayName,
      ),
      child: row,
    );
  }

  Widget _buildRow() {
    final locallyMuted = setting?.muted ?? false;
    final dim = isOnline ? 1.0 : 0.45;

    return Opacity(
      opacity: dim,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: themeState.bgHover,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _avatar(),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    member.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: themeState.textSecondary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ..._badges(locallyMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Initials for now — real pictures arrive with the profile feature.
  Widget _avatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: themeState.bgTertiary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            member.displayName.isNotEmpty
                ? member.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: themeState.textTertiary,
            ),
          ),
        ),
        // Presence dot, ringed in the panel colour so it reads as a cut-out.
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline
                  ? CustomColors.userStatusOnline
                  : themeState.textQuaternary,
              shape: BoxShape.circle,
              border: Border.all(color: themeState.bgPrimary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _badges(bool locallyMuted) {
    final badges = <Widget>[];
    if (member.permissions.isServerAdmin) {
      badges.add(
        Icon(Icons.shield_rounded, size: 13, color: themeState.primary),
      );
    } else if (member.permissions.isChannelManager) {
      badges.add(
        Icon(Icons.build_rounded, size: 12, color: themeState.textQuaternary),
      );
    }
    if (member.isMuted) {
      badges.add(
        const Icon(Icons.mic_off_rounded, size: 13, color: CustomColors.error),
      );
    }
    if (locallyMuted) {
      badges.add(
        const Icon(
          Icons.volume_off_rounded,
          size: 13,
          color: CustomColors.error,
        ),
      );
    }
    return [
      for (final badge in badges) ...[const SizedBox(width: 4), badge],
    ];
  }
}
