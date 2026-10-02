import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Name badge showing participant name and status icons
class ParticipantNameBadge extends StatelessWidget {
  final String name;
  final bool isMicEnabled;
  final bool isMuted;

  /// Drawn as headphones before the microphone, as the sidebar does: being
  /// deafened takes the microphone with it, and a mic alone read as "muted,
  /// but listening".
  final bool isDeafened;
  final bool isScreenshare;

  /// Shown before the name. Defaults to the screen icon for a screen share;
  /// a shared track passes its own, having no picture to put a screen on.
  final IconData? leadingIcon;

  const ParticipantNameBadge({
    super.key,
    required this.name,
    required this.isMicEnabled,
    required this.isMuted,
    this.isDeafened = false,
    this.isScreenshare = false,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final icon = leadingIcon ?? (isScreenshare ? Icons.monitor_rounded : null);
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
                Icon(icon, size: K.iconInline, color: themeState.accentBright),
              // Shortened rather than spilling: the row under a screen
              // share is narrower than a long name, and the badge ran
              // out of its tile and was cut mid-letter.
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
              ),
              if (!isScreenshare && isDeafened)
                const Icon(
                  Icons.headset_off_rounded,
                  size: K.iconInline,
                  color: CustomColors.error,
                ),
              if (!isScreenshare && (!isMicEnabled || isMuted || isDeafened))
                const Icon(
                  Icons.mic_off_rounded,
                  size: K.iconInline,
                  color: CustomColors.error,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
