import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/participant_info.dart';
import '../../../../../../data/classes/participant_setting.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../data/constants.dart';
import '../../../../common/context_menu/context_menu_button.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/hover_builder.dart';
import '../../../../common/speaking_ring.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// A single participant row inside an active voice channel.
class ParticipantListItem extends StatelessWidget {
  final ParticipantInfo participant;
  final ParticipantSetting? setting;
  final Widget? contextMenu;

  const ParticipantListItem({
    super.key,
    required this.participant,
    this.setting,
    this.contextMenu,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => _build(context, hovered),
    );
  }

  Widget _build(BuildContext context, bool hovered) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final isMuted = setting?.muted ?? false;
        final isSpeaking = participant.isSpeaking && !isMuted;

        // The roster, not `participant.name` — that one is a copy of the
        // display name frozen into the LiveKit token when it was minted, so a
        // rename mid-call would leave the old name on screen until the token
        // expired an hour later.
        final name = context.watch<ServerMembersCubit>().state.nameFor(
          participant.userId,
          participant.name,
        );

        final textSecondary = themeState.textSecondary;
        final textQuaternary = themeState.textQuaternary;
        final hoverColor = themeState.bgHover;

        Widget content = Material(
          color: isSpeaking ? themeState.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(K.radiusRow),
          child: InkWell(
            borderRadius: BorderRadius.circular(K.radiusRow),
            hoverColor: hoverColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // The avatar itself carries the speaking state — the same
                  // pulsing ring the voice tiles use, at roster scale.
                  SpeakingRing(
                    isSpeaking: isSpeaking,
                    borderRadius: BorderRadius.circular(
                      22 * K.avatarRadiusRatio,
                    ),
                    child: SquircleAvatar(
                      name: name,
                      seed: participant.userId,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name
                  Expanded(
                    child: Text(
                      participant.isLocal ? '$name (You)' : name,
                      style: AppText.secondary.copyWith(
                        fontWeight: isSpeaking
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSpeaking
                            ? themeState.channelActiveText
                            : isMuted
                            ? textQuaternary
                            : textSecondary,
                        decoration: isMuted ? TextDecoration.lineThrough : null,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Server-side moderation indicators
                  if (participant.isServerDeafened) ...[
                    Tooltip(
                      message: 'Deafened by a moderator',
                      child: Icon(
                        Icons.headset_off,
                        size: 11,
                        color: CustomColors.error.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (participant.isServerMuted) ...[
                    Tooltip(
                      message: 'Muted by a moderator',
                      child: Icon(
                        Icons.mic_off,
                        size: 11,
                        color: CustomColors.error.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Mic icon
                  if (!participant.isServerMuted)
                    _MicIcon(
                      isMuted: isMuted,
                      isMicEnabled: participant.isMicrophoneEnabled,
                    ),
                  // Local mute and volume live in this menu, and nothing on
                  // the row suggested they existed.
                  if (contextMenu != null && !context.layoutMode.isCompact) ...[
                    const SizedBox(width: 6),
                    ContextMenuButton(menu: contextMenu!, visible: hovered),
                  ],
                ],
              ),
            ),
          ),
        );

        if (contextMenu != null) {
          return ContextMenuRegion(contextMenu: contextMenu!, child: content);
        }

        return content;
      },
    );
  }
}

class _MicIcon extends StatelessWidget {
  final bool isMuted;
  final bool isMicEnabled;

  const _MicIcon({required this.isMuted, required this.isMicEnabled});

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => _build(context, hovered),
    );
  }

  Widget _build(BuildContext context, bool hovered) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        if (isMuted) {
          return Icon(
            Icons.volume_off,
            size: 11,
            color: CustomColors.error.withValues(alpha: 0.7),
          );
        }
        if (isMicEnabled) {
          return Icon(Icons.mic, size: 11, color: themeState.textQuaternary);
        }
        return Icon(Icons.mic_off, size: 11, color: CustomColors.error);
      },
    );
  }
}
