import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
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
          iconColor = themeState.primary;
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

                final count = isSelected
                    ? liveKitParticipants.length
                    : presenceUsers.length;

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
                              if (!isSelected && presenceUsers.isNotEmpty)
                                _PresenceAvatarStack(
                                  users: presenceUsers,
                                  themeState: themeState,
                                )
                              else if (count > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: themeState.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: themeState.primary,
                                    ),
                                  ),
                                ),
                              if (isSelected && count == 0)
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
                                    setting: appState
                                        .participantSettings[p.identity],
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

/// Overlapping mini-avatar stack showing who's in a channel you haven't
/// joined — presence at a glance without spending a row per user.
class _PresenceAvatarStack extends StatelessWidget {
  static const _maxAvatars = 3;

  final List<PresenceUser> users;
  final ThemeState themeState;

  const _PresenceAvatarStack({required this.users, required this.themeState});

  @override
  Widget build(BuildContext context) {
    final visible = users.take(_maxAvatars).toList();
    final overflow = users.length - visible.length;

    return Tooltip(
      message: users.map((u) => u.displayName).join(', '),
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20.0 + (visible.length - 1) * 13.0,
            height: 20,
            child: Stack(
              children: [
                for (var i = 0; i < visible.length; i++)
                  Positioned(
                    left: i * 13.0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: themeState.bgActive,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: themeState.bgSecondary,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        visible[i].displayName.isNotEmpty
                            ? visible[i].displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: themeState.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (overflow > 0) ...[
            const SizedBox(width: 4),
            Text(
              '+$overflow',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: themeState.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
