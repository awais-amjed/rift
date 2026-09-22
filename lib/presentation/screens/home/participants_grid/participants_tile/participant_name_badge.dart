import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// Name badge showing participant name and status icons
class ParticipantNameBadge extends StatelessWidget {
  final String name;
  final bool isMicEnabled;
  final bool isMuted;
  final bool isScreenshare;

  /// Shown before the name. Defaults to the screen icon for a screen share;
  /// a shared track passes its own, having no picture to put a screen on.
  final IconData? leadingIcon;

  const ParticipantNameBadge({
    super.key,
    required this.name,
    required this.isMicEnabled,
    required this.isMuted,
    this.isScreenshare = false,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final icon =
            leadingIcon ?? (isScreenshare ? Icons.monitor_rounded : null);
        // Glass over video: translucent panel colour plus a blur, so the
        // name stays readable over a bright frame without blacking it out.
        return ClipRRect(
          borderRadius: BorderRadius.circular(K.radiusRow),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: themeState.bgSecondary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(K.radiusRow),
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (icon != null)
                    Icon(icon, size: 13, color: themeState.accentBright),
                  // Shortened rather than spilling: the row under a screen
                  // share is narrower than a long name, and the badge ran
                  // out of its tile and was cut mid-letter.
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.row.copyWith(
                        color: themeState.textPrimary,
                      ),
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
