import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../theme/custom_colors.dart';

/// Dialog-based context menu for a participant — mute toggle + volume slider.
class ParticipantContextMenu extends StatelessWidget {
  final String identity;
  final String name;

  const ParticipantContextMenu({
    super.key,
    required this.identity,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final setting = state.participantSettings[identity];
        final isMuted = setting?.muted ?? false;
        final volume = setting?.volume ?? 1.0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark
            ? const Color(0xFF1E1E21)
            : CustomColors.bgSecondaryLight;
        final borderColor = isDark
            ? CustomColors.borderPrimaryDark
            : CustomColors.borderPrimaryLight;
        final textPrimary = isDark
            ? CustomColors.textPrimaryDark
            : CustomColors.textPrimaryLight;
        final textSecondary = isDark
            ? CustomColors.textSecondaryDark
            : CustomColors.textSecondaryLight;
        final textQuaternary = isDark
            ? CustomColors.textQuaternaryDark
            : CustomColors.textQuaternaryLight;

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 224),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PARTICIPANT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: textQuaternary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: borderColor),
                  const SizedBox(height: 4),
                  // Mute toggle
                  _MenuItem(
                    icon: isMuted ? Icons.volume_off : Icons.volume_up,
                    label: isMuted ? 'Unmute for me' : 'Mute for me',
                    isDangerous: isMuted,
                    onTap: () {
                      context.read<AppCubit>().setParticipantSetting(
                        identity,
                        muted: !isMuted,
                      );
                    },
                  ),
                  // Volume slider
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'VOLUME',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: textQuaternary,
                              ),
                            ),
                            Text(
                              isMuted ? '—' : '${(volume * 100).round()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: CustomColors.primary,
                            inactiveTrackColor: isDark
                                ? CustomColors.bgActiveDark
                                : CustomColors.bgActiveLight,
                            thumbColor: CustomColors.primary,
                          ),
                          child: Slider(
                            value: isMuted ? 0 : volume,
                            min: 0,
                            max: 1,
                            onChanged: isMuted
                                ? null
                                : (v) {
                                    context
                                        .read<AppCubit>()
                                        .setParticipantSetting(
                                          identity,
                                          volume: v,
                                        );
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDangerous;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.isDangerous = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDangerous
        ? CustomColors.error
        : isDark
        ? CustomColors.textSecondaryDark
        : CustomColors.textSecondaryLight;
    final bgColor = isDangerous
        ? CustomColors.error.withOpacity(0.1)
        : Colors.transparent;
    final hoverColor = isDark
        ? CustomColors.bgHoverDark
        : CustomColors.bgHoverLight;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: hoverColor,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
