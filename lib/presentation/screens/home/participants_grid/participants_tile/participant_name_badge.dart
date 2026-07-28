import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// Name badge showing participant name and status icons
class ParticipantNameBadge extends StatelessWidget {
  final String name;
  final bool isMicEnabled;
  final bool isMuted;
  final bool isScreenshare;

  const ParticipantNameBadge({
    super.key,
    required this.name,
    required this.isMicEnabled,
    required this.isMuted,
    this.isScreenshare = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                (themeState.isDarkTheme
                        ? themeState.bgTertiary
                        : themeState.bgSecondary)
                    .withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isScreenshare) ...[
                Icon(Icons.monitor, size: 13, color: themeState.primary),
                const SizedBox(width: 6),
              ],
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              if (!isScreenshare && (!isMicEnabled || isMuted)) ...[
                const SizedBox(width: 6),
                Icon(Icons.mic_off, size: 13, color: CustomColors.error),
              ],
            ],
          ),
        );
      },
    );
  }
}
