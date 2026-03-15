import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../theme/custom_colors.dart';
import '../../../sidebar/widgets/participant_context_menu.dart';
import '../../../sidebar/widgets/participant_list_item.dart';

/// Tile for displaying a voice channel with participants.
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
        Color bgColor;
        Color textColor;
        Color iconColor;
        BorderSide? borderSide;

        if (isSelected) {
          bgColor = themeState.channelActiveBg;
          textColor = themeState.channelActiveText;
          iconColor = CustomColors.primary;
          borderSide = BorderSide(color: themeState.channelActiveBorder);
        } else {
          bgColor = Colors.transparent;
          textColor = themeState.textSecondary;
          iconColor = themeState.textQuaternary;
          borderSide = null;
        }

        final hoverColor = themeState.bgHover;

        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            final liveKitParticipants = isSelected ? appState.participants : [];

            return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
              builder: (context, presenceState) {
                final presenceUsers = isSelected
                    ? const <PresenceUser>[]
                    : presenceState.usersIn(channel.id);

                final count =
                    isSelected ? liveKitParticipants.length : presenceUsers.length;

                return Column(
                  children: [
                    Material(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        hoverColor: hoverColor,
                        onTap: onTap,
                        child: Container(
                          decoration: borderSide != null
                              ? BoxDecoration(
                                  border: Border.all(
                                    color: borderSide.color,
                                    width: borderSide.width,
                                  ),
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
                              if (count > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CustomColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: CustomColors.primary,
                                    ),
                                  ),
                                ),
                              if (isSelected && count == 0)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: CustomColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // LiveKit participants (when in the channel)
                    if (isSelected && liveKitParticipants.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Container(
                          margin: const EdgeInsets.only(top: 2, bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: themeState.borderPrimary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Column(
                            children: liveKitParticipants
                                .where((p) => !p.isScreenshare)
                                .map(
                                  (p) => ParticipantListItem(
                                    participant: p,
                                    setting: appState.participantSettings[p.identity],
                                    contextMenu: ParticipantContextMenu(
                                      identity: p.identity,
                                      name: p.name,
                                      isLocal: p.isLocal,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    // Presence users (when not in the channel, others are visible)
                    if (!isSelected && presenceUsers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Container(
                          margin: const EdgeInsets.only(top: 2, bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: themeState.borderPrimary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Column(
                            children: presenceUsers
                                .map((u) => _PresenceUserRow(
                                      user: u,
                                      themeState: themeState,
                                    ))
                                .toList(),
                          ),
                        ),
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

/// Compact row for a presence user (not yet in the channel via LiveKit).
class _PresenceUserRow extends StatelessWidget {
  final PresenceUser user;
  final ThemeState themeState;

  const _PresenceUserRow({required this.user, required this.themeState});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: themeState.bgActive,
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
