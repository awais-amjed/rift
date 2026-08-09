import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../data/classes/participant_info.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../common/nav_row.dart';
import '../../../../../../theme/app_text.dart';
import '../channel_context_menu.dart';
import 'widgets/channel_drop_target.dart';
import 'widgets/channel_roster.dart';
import 'widgets/live_badge.dart';

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
          builder: (context, appState) {
            // Screenshare pseudo-participants aren't people.
            final participants = isSelected
                ? appState.participants.where((p) => !p.isScreenshare).toList()
                : const <ParticipantInfo>[];

            return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
              builder: (context, presenceState) {
                final presenceUsers = isSelected
                    ? const <PresenceUser>[]
                    : presenceState.usersIn(channel.id);
                final isOccupied =
                    isSelected ||
                    participants.isNotEmpty ||
                    presenceUsers.isNotEmpty;

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
                        label: channel.name,
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
        color: isSelected ? null : themeState.bgHover,
        gradient: isSelected ? themeState.activeRowGradient : null,
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
            child: _buildHeader(context, themeState),
          ),
          if (participants.isNotEmpty || presenceUsers.isNotEmpty)
            ChannelRoster(
              channelId: channel.id,
              participants: participants,
              presenceUsers: presenceUsers,
              settings: appState.participantSettings,
              themeState: themeState,
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeState themeState) {
    return InkWell(
      borderRadius: BorderRadius.circular(K.radiusRow),
      onTap: onTap,
      child: Row(
        spacing: 9,
        children: [
          Icon(
            Icons.volume_up_rounded,
            size: 16,
            color: isSelected
                ? themeState.accentBright
                : themeState.textTertiary,
          ),
          Expanded(
            child: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.row.copyWith(
                color: isSelected
                    ? themeState.channelActiveText
                    : themeState.textSecondary,
              ),
            ),
          ),
          if (isSelected) const LiveBadge(),
        ],
      ),
    );
  }
}
