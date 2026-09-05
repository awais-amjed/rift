import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_text.dart';
import '../../../../../data/constants.dart';

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
                  size: 17,
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
                        'Share Audio',
                        style: AppText.row.copyWith(
                          color: shareAudio
                              ? themeState.textPrimary
                              : themeState.textSecondary,
                        ),
                      ),
                      Text(
                        shareAudio
                            ? 'System audio will be captured'
                            : 'No audio will be shared',
                        style: AppText.label.copyWith(
                          color: themeState.textQuaternary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSwitch(value: shareAudio, onChanged: (_) => onToggle()),
              ],
            ),
          ),
        );
      },
    );
  }
}
