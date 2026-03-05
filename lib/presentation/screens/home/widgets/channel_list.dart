import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/enums/channel_type.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import 'participant_list_item.dart';
import 'participant_context_menu.dart';

/// Lists all channels grouped by type. Voice channels show live participants.
class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final String? selectedChannelId;
  final ValueChanged<String?>? onChannelSelect;

  const ChannelList({
    super.key,
    required this.channels,
    this.selectedChannelId,
    this.onChannelSelect,
  });

  @override
  Widget build(BuildContext context) {
    final textChannels = channels
        .where((c) => c.channelType == ChannelType.text)
        .toList();
    final voiceChannels = channels
        .where((c) => c.channelType == ChannelType.voice)
        .toList();

    if (channels.isEmpty) {
      return Expanded(child: _EmptyChannels());
    }

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (textChannels.isNotEmpty) ...[
            _SectionHeader(label: 'Text'),
            const SizedBox(height: 4),
            ...textChannels.map((ch) => _TextChannelTile(channel: ch)),
            const SizedBox(height: 16),
          ],
          if (voiceChannels.isNotEmpty) ...[
            _SectionHeader(label: 'Voice'),
            const SizedBox(height: 4),
            ...voiceChannels.map(
              (ch) => _VoiceChannelTile(
                channel: ch,
                isSelected: selectedChannelId == ch.id,
                onTap: () => onChannelSelect?.call(
                  selectedChannelId == ch.id ? null : ch.id,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final textQuaternary = context.read<ThemeCubit>().state.textQuaternary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: textQuaternary,
        ),
      ),
    );
  }
}

class _TextChannelTile extends StatelessWidget {
  final Channel channel;

  const _TextChannelTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
    final textSecondary = themeState.textSecondary;
    final textQuaternary = themeState.textQuaternary;
    final hoverColor = themeState.bgHover;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: hoverColor,
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.tag, size: 17, color: textQuaternary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channel.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback? onTap;

  const _VoiceChannelTile({
    required this.channel,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;

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
                            color: CustomColors.primary.withOpacity(0.15),
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
                            setting: appState.participantSettings[p.identity],
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

class _EmptyChannels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tag,
            size: 32,
            color: isDark
                ? CustomColors.textQuaternaryDark
                : CustomColors.textQuaternaryLight,
          ),
          const SizedBox(height: 8),
          Text(
            'No channels yet',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? CustomColors.textTertiaryDark
                  : CustomColors.textTertiaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
