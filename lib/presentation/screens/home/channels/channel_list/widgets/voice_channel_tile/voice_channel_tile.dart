import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../common/hover_builder.dart';
import '../../../../../../theme/app_motion.dart';
import '../../../../../../theme/theme_context.dart';
import '../channel_context_menu.dart';
import '../channel_settings_gear.dart';
import 'widgets/channel_drop_target.dart';
import 'widgets/channel_roster.dart';
import 'widgets/roster_row_metrics.dart';
import 'widgets/voice_channel_tile_header.dart';

/// Over the widget budget and one job: a voice channel, as a row or as a card
/// of the people in it.
///
/// A voice channel in the sidebar — Discord-style, showing who is in it.
///
/// Empty channels look like ordinary rows. The moment anyone is inside, the
/// row becomes a card: a bordered box holding the channel and its people. That
/// promotion is the point — a call in progress is the most important thing in
/// the sidebar, and it should look different in kind, not just in colour. It
/// is one widget in both states, so the promotion can be animated.
class VoiceChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback? onTap;

  const VoiceChannelTile({
    super.key,
    required this.channel,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<AppCubit, AppState>(
      // This tile reads two of `AppState`'s thirty fields, and there is one
      // of it per voice channel in the sidebar. Without this, a hover flag
      // or an audio preference rebuilt every one of them, along with each
      // tile's whole roster.
      //
      // `identical` is the right test rather than `==`: the cubit replaces
      // both wholesale — `participantSettings` is copied into a new map on
      // every change — so a shared instance really does mean unchanged, and
      // neither has a value equality to fall back on anyway.
      buildWhen: (previous, current) =>
          !identical(previous.participants, current.participants) ||
          !identical(previous.participantSettings, current.participantSettings),
      builder: (context, appState) {
        return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
          builder: (context, presenceState) {
            // A share's connection isn't a person, and anyone
            // who has since announced another channel has left this one —
            // LiveKit just hasn't said so yet (ChannelPresenceState.
            // isElsewhere).
            final participants = isSelected
                ? [
                    for (final participant in appState.participants)
                      if (!participant.isShare &&
                          !presenceState.isElsewhere(
                            participant.userId,
                            channel.id,
                          ))
                        participant,
                  ]
                : const <ParticipantInfo>[];
            final presenceUsers = isSelected
                ? const <PresenceUser>[]
                : presenceState.usersIn(channel.id);
            // Bots called into this channel, arrived or not. A summon that
            // nothing answered is the case this is for: it makes the
            // channel occupied enough to draw a roster, which is the only
            // place it can be seen or sent away.
            final summoned = context.watch<VoiceListenersCubit>().summoned(
              channel.id,
            );
            final isOccupied =
                isSelected ||
                participants.isNotEmpty ||
                presenceUsers.isNotEmpty ||
                summoned.isNotEmpty;

            // An empty channel is the most likely place to drop someone,
            // so it catches a drag as readily as an occupied one — and a
            // drag over it raises the card, accent border and all, to say
            // where the drop would land.
            return ChannelDropTarget(
              channelId: channel.id,
              builder: (context, isTargeted) => TweenAnimationBuilder<double>(
                // No `begin`: the first build starts where it is, so a list
                // opening onto calls in progress doesn't animate them all in.
                tween: Tween(end: isOccupied || isTargeted ? 1 : 0),
                // Your own join answers your click; anyone else's is an
                // arrival you didn't cause, and gets the longer, legible one.
                duration: isSelected ? AppMotion.state : AppMotion.enter,
                curve: AppMotion.settle,
                builder: (context, t, _) => _buildCard(
                  context,
                  themeState,
                  appState,
                  t: t,
                  participants: participants,
                  presenceUsers: presenceUsers,
                  summoned: summoned,
                  isTargeted: isTargeted,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The channel as a card, [t] of the way to being one: 0 is the plain row
  /// an empty channel is, 1 the card a call makes it.
  ///
  /// One shape at every [t] rather than a row swapped for a card, so a call
  /// starting fades the card in around a name that stays put — the border is
  /// always there, just transparent, and the side padding the card grows is
  /// taken back out of the header's, so the glyph never moves sideways.
  Widget _buildCard(
    BuildContext context,
    ThemeState themeState,
    AppState appState, {
    required double t,
    required List<ParticipantInfo> participants,
    required List<PresenceUser> presenceUsers,
    List<SummonedBot> summoned = const [],
    bool isTargeted = false,
  }) {
    final side = RosterRowMetrics.cardPadding * t;
    // The channel you are *in* takes the accent, the same way a selected
    // row does; a channel that merely has people in it stays neutral. Both
    // are cards, so the difference says which call is yours. A drag hovering
    // over it borrows the accent border — where this drop would land.
    final fill = isSelected ? themeState.channelActiveBg : themeState.bgHover;
    final edge = isTargeted
        ? themeState.accentBright
        : (isSelected
              ? themeState.channelActiveBorder
              : themeState.borderElevated);

    // Padded above and below at every [t], so each row — the header and
    // every person — lights up as a rounded row clear of the card's corners,
    // and the name sits where the card will put it.
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: RosterRowMetrics.cardPadding,
        horizontal: side,
      ),
      decoration: BoxDecoration(
        color: Color.lerp(fill.withValues(alpha: 0), fill, t),
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(
          color: Color.lerp(edge.withValues(alpha: 0), edge, t)!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only the header carries the channel menu: the participant rows
          // below have their own, and nesting the two would make which one you
          // got depend on the pixel you happened to right-click.
          ChannelContextMenu.wrap(
            context: context,
            channel: channel,
            child: HoverBuilder(
              builder: (context, hovered) => VoiceChannelTileHeader(
                channel: channel,
                card: t,
                horizontalPadding: RosterRowMetrics.headerInset - 1 - side,
                startedAt: context
                    .watch<ChannelPresenceCubit>()
                    .state
                    .callStartedAt[channel.id],
                gear: ChannelSettingsGear.beside(
                  context,
                  null,
                  channel: channel,
                  hovered: hovered,
                ),
                isSelected: isSelected,
                listeners: context.watch<VoiceListenersCubit>().listening(
                  channel.id,
                ),
                onTap: onTap,
              ),
            ),
          ),
          // Always there, empty or not, so the first person into an empty
          // channel animates in like everyone after them.
          ChannelRoster(
            channelId: channel.id,
            participants: participants,
            presenceUsers: presenceUsers,
            summoned: summoned,
            settings: appState.participantSettings,
          ),
        ],
      ),
    );
  }
}
