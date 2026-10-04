import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Audio sharing toggle widget
class AudioToggle extends StatelessWidget {
  final bool shareAudio;
  final VoidCallback onToggle;

  const AudioToggle({
    super.key,
    required this.shareAudio,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: AppMotion.state,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: shareAudio
                ? themeState.primary.withValues(alpha: 0.08)
                : themeState.bgTertiary,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(
              color: shareAudio
                  ? themeState.primary.withValues(alpha: 0.35)
                  : themeState.borderPrimary,
            ),
          ),
          child: Row(
            children: [
              Icon(
                shareAudio ? Icons.volume_up : Icons.volume_off,
                size: K.iconButton,
                color: shareAudio
                    ? themeState.primary
                    : themeState.textQuaternary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share audio',
                      style: AppText.row.copyWith(
                        color: shareAudio
                            ? themeState.textPrimary
                            : themeState.textSecondary,
                      ),
                    ),
                    Text(
                      !shareAudio
                          ? 'No audio will be shared'
                          // Linux shares one app's sound, picked below.
                          : HostPlatform.picksShareAudioSource
                          ? 'The app picked below will be heard'
                          : 'System audio will be captured',
                      style: AppText.label.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(value: shareAudio, onChanged: (_) => onToggle()),
            ],
          ),
        ),
      ),
    );
  }
}
