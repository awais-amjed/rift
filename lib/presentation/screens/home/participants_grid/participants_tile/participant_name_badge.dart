import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/app_text.dart';

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
        // Glass over video: translucent panel colour plus a blur, so the
        // name stays readable over a bright frame without blacking it out.
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: themeState.bgSecondary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (isScreenshare)
                    Icon(
                      Icons.monitor_rounded,
                      size: 13,
                      color: themeState.accentBright,
                    ),
                  Text(
                    name,
                    style: AppText.row.copyWith(
                      fontSize: 12.5,
                      color: themeState.textPrimary,
                    ),
                  ),
                  if (!isScreenshare && (!isMicEnabled || isMuted))
                    const Icon(
                      Icons.mic_off_rounded,
                      size: 13,
                      color: CustomColors.error,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
