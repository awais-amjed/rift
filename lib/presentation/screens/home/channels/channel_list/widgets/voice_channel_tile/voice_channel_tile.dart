import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../data/classes/participant_setting.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../../logic/services/participant_roster.dart';
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

  /// Wraps the header so a manager can drag the channel to a new place. Only
  /// the header: the people below it are dragged too, into other calls.
  final Widget Function(Widget header)? headerGrip;

  const VoiceChannelTile({
    super.key,
    required this.channel,
    required this.isSelected,
    this.onTap,
    this.headerGrip,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // Selected rather than built on: there is one of these per voice channel
    // in the sidebar, and `AppState` changes with every hover, preference and
    // breath anybody in the call takes. Settings are replaced wholesale on
    // every change, so the map's own `==` (identity) is the right test.
    final settings = context.select<AppCubit, Map<String, ParticipantSetting>>(
      (c) => c.state.participantSettings,
    );
    // Only your own call has live participants, and only a change to who is in
    // it, or how, redraws the card. Who is speaking is left to each row's ring
    // (`ParticipantListItem`), or every voice channel rebuilt several times a
    // second while anyone talked.
    final live = context
        .select<AppCubit, RosterApartFromSpeaking>(
          (c) => RosterApartFromSpeaking(
            isSelected ? c.state.participants : const [],
          ),
        )
        .participants;
    return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
      builder: (context, presenceState) {
        // A share's connection isn't a person, and anyone
        // who has since announced another channel has left this one —
        // LiveKit just hasn't said so yet (ChannelPresenceState.
        // isElsewhere).
        final participants = isSelected
            ? [
                for (final participant in live)
                  if (!participant.isShare &&
                      !presenceState.isElsewhere(
                        participant.userId,
                        channel.id,
                      ))
                    participant,
              ]
            : const <ParticipantInfo>[];
        // In your own call LiveKit is the source, but it names the others
        // a moment after you connect. Until it does, presence still says
        // they are here — and dropping them for that moment folded
        // everyone out of the card and back in as you joined.
        final presenceUsers = isSelected
            ? [
                for (final user in presenceState.usersIn(channel.id))
                  if (!participants.any((p) => p.userId == user.userId)) user,
              ]
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
              settings,
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
  }

  static Widget _bare(Widget header) => header;

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
    Map<String, ParticipantSetting> settings, {
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
          (headerGrip ?? _bare)(
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
          ),
          // Always there, empty or not, so the first person into an empty
          // channel animates in like everyone after them.
          ChannelRoster(
            channelId: channel.id,
            participants: participants,
            presenceUsers: presenceUsers,
            summoned: summoned,
            settings: settings,
          ),
        ],
      ),
    );
  }
}
