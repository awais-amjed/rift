import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../sidebar/widgets/participant_context_menu.dart';
import '../../../sidebar/widgets/participant_list_item.dart';

/// Tile for a voice channel. Shows the channel name and — Discord-style — the
/// list of people currently in it: the live LiveKit participants when it's the
/// channel you're in, otherwise the Realtime-presence members of any other
/// channel.
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
        final Color bgColor;
        final Color textColor;
        final Color iconColor;
        final BorderSide? borderSide;

        if (isSelected) {
          bgColor = themeState.channelActiveBg;
          textColor = themeState.channelActiveText;
          iconColor = themeState.primary;
          borderSide = BorderSide(color: themeState.channelActiveBorder);
        } else {
          bgColor = Colors.transparent;
          textColor = themeState.textSecondary;
          iconColor = themeState.textQuaternary;
          borderSide = null;
        }

        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            final liveKitParticipants = isSelected ? appState.participants : [];
            // Exclude screenshare pseudo-participants — they aren't people.
            final voiceParticipants = liveKitParticipants
                .where((p) => !p.isScreenshare)
                .toList();

            return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
              builder: (context, presenceState) {
                final presenceUsers = isSelected
                    ? const <PresenceUser>[]
                    : presenceState.usersIn(channel.id);

                final memberCount = isSelected
                    ? voiceParticipants.length
                    : presenceUsers.length;

                return Column(
                  children: [
                    Material(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        hoverColor: themeState.bgHover,
                        onTap: onTap,
                        child: Container(
                          decoration: borderSide != null
                              ? BoxDecoration(
                                  border: Border.all(color: borderSide.color),
                                  borderRadius: BorderRadius.circular(10),
                                )
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.volume_up, size: 17, color: iconColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  channel.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              // Empty channel you're in → a small "live" dot.
                              if (isSelected && memberCount == 0)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: themeState.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Members in the channel you're connected to (full LiveKit
                    // state: speaking, mute, moderation, context menu).
                    if (isSelected && voiceParticipants.isNotEmpty)
                      _MemberColumn(
                        themeState: themeState,
                        children: voiceParticipants
                            .map(
                              (p) => ParticipantListItem(
                                participant: p,
                                setting: appState.participantSettings[p.userId],
                                contextMenu: ParticipantContextMenu(
                                  identity: p.identity,
                                  name: p.name,
                                  isLocal: p.isLocal,
                                ),
                              ),
                            )
                            .toList(),
                      ),

                    // Members in any other channel (Realtime presence — name
                    // only; live mic/speaking state isn't available remotely).
                    if (!isSelected && presenceUsers.isNotEmpty)
                      _MemberColumn(
                        themeState: themeState,
                        children: presenceUsers
                            .map(
                              (u) => _PresenceMemberRow(
                                user: u,
                                themeState: themeState,
                              ),
                            )
                            .toList(),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The indented, left-ruled container that holds a voice channel's member rows.
class _MemberColumn extends StatelessWidget {
  final ThemeState themeState;
  final List<Widget> children;

  const _MemberColumn({required this.themeState, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: themeState.borderPrimary, width: 1.5),
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
}

/// A member of a voice channel you're not in — rendered from Realtime presence,
/// so we only have their name (no live mic/speaking state). Visually matches
/// [ParticipantListItem] minus the mic controls.
class _PresenceMemberRow extends StatelessWidget {
  final PresenceUser user;
  final ThemeState themeState;

  const _PresenceMemberRow({required this.user, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: themeState.bgTertiary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: themeState.textQuaternary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: themeState.textSecondary,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
