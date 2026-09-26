import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/participant_info.dart';
import '../../../../../data/classes/participant_setting.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/hover_builder.dart';
import '../../../../common/member_avatar.dart';
import '../../../../common/speaking_ring.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/roster_row_metrics.dart';
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
    final themeState = context.theme;
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

    // A tint rather than an ink well: clicking a person does nothing —
    // their profile and everything else is in the menu — and a well with
    // no tap would not light up at all.
    //
    // Speaking is the ring's alone. The row used to take a tint and the name
    // a heavier, brighter weight as well, so a busy call was a column of
    // rows flashing on and off — and the weight change reflowed the name
    // with every breath.
    Widget content = Material(
      // Transparent at rest, not null: a null Material paints the canvas
      // colour, which drew a dark strip inside the channel's card.
      color: hovered ? hoverColor : Colors.transparent,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: metrics.padding,
        child: Row(
          children: [
            // The avatar itself carries the speaking state — the same
            // pulsing ring the voice tiles use, at roster scale.
            SpeakingRing(
              isSpeaking: isSpeaking,
              // A tight halo: at the tile's bloom it spread across the whole
              // row and the avatar read as framed rather than lit.
              bloom: 0.35,
              borderRadius: BorderRadius.circular(
                metrics.avatarSize * K.avatarRadiusRatio,
              ),
              child: MemberAvatar(
                userId: participant.userId,
                name: name,
                size: metrics.avatarSize,
              ),
            ),
            const SizedBox(width: 8),
            // Name
            // Muted for you is dimmed, not struck through: the red icon at
            // the end already says why, and a line through somebody's name
            // read as their having been removed.
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: name,
                  children: [
                    if (participant.isLocal)
                      TextSpan(
                        text: ' (you)',
                        style: TextStyle(
                          color: textQuaternary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RosterRowMetrics.of(context).nameStyle.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isMuted ? textQuaternary : textSecondary,
                ),
              ),
            ),
            // What they are doing: sharing, deafened, muted.
            VoiceStatusRowIcons(participant: participant, mutedForYou: isMuted),
          ],
        ),
      ),
    );

    if (contextMenu != null) {
      return ContextMenuRegion(contextMenu: contextMenu!, child: content);
    }

    return content;
  }
}
