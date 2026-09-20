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
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/roster_row_metrics.dart';
import '../../profile/person/show_person_profile.dart';
import 'voice_status_row_icons.dart';

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
        final metrics = RosterRowMetrics.of(context);
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
          // Transparent at rest, not null: a null Material paints the canvas
          // colour, which drew a dark strip inside the channel's card.
          color: isSpeaking
              ? themeState.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(K.radiusRow),
          child: InkWell(
            borderRadius: BorderRadius.circular(K.radiusRow),
            hoverColor: hoverColor,
            // The well was already here, lighting on hover with nothing
            // behind it. A name in a call is one of the likeliest places to
            // wonder who somebody is.
            onTap: () => showMemberProfile(
              context,
              userId: participant.userId,
              name: name,
            ),
            child: Padding(
              padding: metrics.padding,
              child: Row(
                children: [
                  // The avatar itself carries the speaking state — the same
                  // pulsing ring the voice tiles use, at roster scale.
                  SpeakingRing(
                    isSpeaking: isSpeaking,
                    borderRadius: BorderRadius.circular(
                      metrics.avatarSize * K.avatarRadiusRatio,
                    ),
                    child: SquircleAvatar(
                      name: name,
                      seed: participant.userId,
                      size: metrics.avatarSize,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name
                  Expanded(
                    child: Text(
                      participant.isLocal ? '$name (You)' : name,
                      style: RosterRowMetrics.of(context).nameStyle.copyWith(
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
                  // What they are doing: sharing, deafened, muted.
                  VoiceStatusRowIcons(
                    participant: participant,
                    mutedForYou: isMuted,
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
