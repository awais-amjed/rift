import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/participant_info.dart';
import '../../../../../data/classes/participant_setting.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// A single participant row inside an active voice channel.
class ParticipantListItem extends StatelessWidget {
  final ParticipantInfo participant;
  final ParticipantSetting? setting;
  final VoidCallback? onLongPress;

  const ParticipantListItem({
    super.key,
    required this.participant,
    this.setting,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final isMuted = setting?.muted ?? false;
        final isSpeaking = participant.isSpeaking && !isMuted;

        final textSecondary = themeState.textSecondary;
        final textQuaternary = themeState.textQuaternary;
        final bgTertiary = themeState.bgTertiary;
        final hoverColor = themeState.bgHover;

        return GestureDetector(
          onLongPress: participant.isLocal ? null : onLongPress,
          child: Material(
            color: isSpeaking
                ? CustomColors.primary.withValues(alpha: 0.08)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: hoverColor,
              onLongPress: participant.isLocal ? null : onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    // Avatar dot
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isSpeaking ? CustomColors.primary : bgTertiary,
                        shape: BoxShape.circle,
                        boxShadow: isSpeaking
                            ? [
                                BoxShadow(
                                  color: CustomColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        participant.name.isNotEmpty
                            ? participant.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isSpeaking ? Colors.white : textQuaternary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Name
                    Expanded(
                      child: Text(
                        participant.isLocal
                            ? '${participant.name} (You)'
                            : participant.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isSpeaking
                              ? CustomColors.primary
                              : isMuted
                              ? textQuaternary
                              : textSecondary,
                          decoration: isMuted
                              ? TextDecoration.lineThrough
                              : null,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Mic icon
                    _MicIcon(
                      isMuted: isMuted,
                      isMicEnabled: participant.isMicrophoneEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MicIcon extends StatelessWidget {
  final bool isMuted;
  final bool isMicEnabled;

  const _MicIcon({required this.isMuted, required this.isMicEnabled});

  @override
  Widget build(BuildContext context) {
    final textQuaternary = context.read<ThemeCubit>().state.textQuaternary;

    if (isMuted) {
      return Icon(
        Icons.volume_off,
        size: 11,
        color: CustomColors.error.withValues(alpha: 0.7),
      );
    }
    if (isMicEnabled) {
      return Icon(Icons.mic, size: 11, color: textQuaternary);
    }
    return Icon(Icons.mic_off, size: 11, color: CustomColors.error);
  }
}
