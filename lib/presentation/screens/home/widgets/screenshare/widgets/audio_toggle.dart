import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';
import 'toggle_pill.dart';

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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return GestureDetector(
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: shareAudio
                  ? CustomColors.primary.withValues(alpha: 0.08)
                  : themeState.bgTertiary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: shareAudio
                    ? CustomColors.primary.withValues(alpha: 0.35)
                    : themeState.borderPrimary,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  shareAudio ? Icons.volume_up : Icons.volume_off,
                  size: 17,
                  color: shareAudio
                      ? CustomColors.primary
                      : themeState.textQuaternary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share Audio',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: shareAudio
                              ? themeState.textPrimary
                              : themeState.textSecondary,
                        ),
                      ),
                      Text(
                        shareAudio
                            ? 'System audio will be captured'
                            : 'No audio will be shared',
                        style: TextStyle(
                          fontSize: 11,
                          color: themeState.textQuaternary,
                        ),
                      ),
                    ],
                  ),
                ),
                TogglePill(active: shareAudio),
              ],
            ),
          ),
        );
      },
    );
  }
}
