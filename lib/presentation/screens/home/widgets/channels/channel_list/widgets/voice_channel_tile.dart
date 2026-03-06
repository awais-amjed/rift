import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/channel.dart';
import '../../../../../../../logic/cubits/app/app_cubit.dart';
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
            final participants = isSelected ? appState.participants : [];

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
                          if (isSelected && participants.isNotEmpty)
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
                                '${participants.length}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: CustomColors.primary,
                                ),
                              ),
                            ),
                          if (isSelected && participants.isEmpty)
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
                // Participant list under active channel
                if (isSelected && participants.isNotEmpty)
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
                        children: participants
                            .map(
                              (p) => ParticipantListItem(
                                participant: p,
                                setting:
                                    appState.participantSettings[p.identity],
                                onLongPress: () {
                                  _showParticipantContextMenu(
                                    context,
                                    p.identity,
                                    p.name,
                                  );
                                },
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
  }

  void _showParticipantContextMenu(
    BuildContext context,
    String identity,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (_) => ParticipantContextMenu(identity: identity, name: name),
    );
  }
}
