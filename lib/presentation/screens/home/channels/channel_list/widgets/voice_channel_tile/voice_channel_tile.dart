import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../common/nav_row.dart';
import '../channel_context_menu.dart';
import '../channel_lock_badge.dart';
import 'widgets/channel_drop_target.dart';
import 'widgets/channel_roster.dart';
import 'widgets/voice_channel_tile_header.dart';
import 'widgets/voice_listening_badge.dart';

/// A voice channel in the sidebar — Discord-style, showing who is in it.
///
/// Empty channels are ordinary rows. The moment anyone is inside, the row
/// becomes a card: a bordered box holding the channel and its people. That
/// promotion is the point — a call in progress is the most important thing in
/// the sidebar, and it should look different in kind, not just in colour.
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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
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
              !identical(
                previous.participantSettings,
                current.participantSettings,
              ),
          builder: (context, appState) {
            return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
              builder: (context, presenceState) {
                // Screenshare pseudo-participants aren't people, and anyone
                // who has since announced another channel has left this one —
                // LiveKit just hasn't said so yet (ChannelPresenceState.
                // isElsewhere).
                final participants = isSelected
                    ? [
                        for (final participant in appState.participants)
                          if (!participant.isScreenshare &&
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
                // so it catches a drag as readily as an occupied one.
                if (!isOccupied) {
                  return ChannelDropTarget(
                    channelId: channel.id,
                    builder: (context, isTargeted) => ChannelContextMenu.wrap(
                      context: context,
                      channel: channel,
                      child: NavRow(
                        icon: Icons.volume_up_rounded,
                        // An empty voice channel is a plain row, not the card
                        // below, so the lock has to be put on twice. Missing
                        // here is the case you would never notice by reading:
                        // an empty channel is exactly the one nobody is in.
                        iconBadge: channel.isPrivate
                            ? ChannelLockBadge()
                            : null,
                        label: channel.name,
                        trailing: VoiceListeningBadge(
                          listeners: context
                              .watch<VoiceListenersCubit>()
                              .listening(channel.id),
                        ),
                        onTap: onTap,
                        isSelected: isTargeted,
                      ),
                    ),
                  );
                }

                return ChannelDropTarget(
                  channelId: channel.id,
                  builder: (context, isTargeted) => _buildCard(
                    context,
                    themeState,
                    appState,
                    participants: participants,
                    presenceUsers: presenceUsers,
                    summoned: summoned,
                    isTargeted: isTargeted,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    ThemeState themeState,
    AppState appState, {
    required List<ParticipantInfo> participants,
    required List<PresenceUser> presenceUsers,
    List<SummonedBot> summoned = const [],
    bool isTargeted = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(9),
      // The channel you are *in* takes the accent, the same way a selected
      // row does; a channel that merely has people in it stays neutral. Both
      // are cards, so the difference says which call is yours. A drag hovering
      // over it borrows the accent border — where this drop would land.
      decoration: BoxDecoration(
        color: isSelected ? themeState.channelActiveBg : themeState.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(
          color: isTargeted
              ? themeState.accentBright
              : (isSelected
                    ? themeState.channelActiveBorder
                    : themeState.borderElevated),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 7,
        children: [
          // Only the header carries the channel menu: the participant rows
          // below have their own, and nesting the two would make which one you
          // got depend on the pixel you happened to right-click.
          ChannelContextMenu.wrap(
            context: context,
            channel: channel,
            child: VoiceChannelTileHeader(
              channel: channel,

              isSelected: isSelected,
              listeners: context.watch<VoiceListenersCubit>().listening(
                channel.id,
              ),
              onTap: onTap,
            ),
          ),
          if (participants.isNotEmpty ||
              presenceUsers.isNotEmpty ||
              summoned.isNotEmpty)
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
