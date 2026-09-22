import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Summary display of selected screen share settings
class SettingsSummary extends StatelessWidget {
  final bool captureFullScreen;
  final String resolution;
  final int fps;
  final int bitrate;
  final bool shareAudio;
  final String codec;

  const SettingsSummary({
    super.key,
    required this.captureFullScreen,
    required this.resolution,
    required this.fps,
    required this.bitrate,
    required this.shareAudio,
    required this.codec,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderPrimary),
      ),
      child: Center(
        child: RichText(
          text: TextSpan(
            style: AppText.rowQuiet.copyWith(color: themeState.textSecondary),
            children: [
              TextSpan(
                text: captureFullScreen ? 'Screen' : 'Window',
                style: AppText.strong,
              ),
              const TextSpan(text: ' · '),
              TextSpan(text: resolution, style: AppText.strong),
              const TextSpan(text: ' · '),
              TextSpan(text: '$fps fps', style: AppText.strong),
              const TextSpan(text: ' · '),
              TextSpan(text: '$bitrate Mbps', style: AppText.strong),
              const TextSpan(text: ' · '),
              TextSpan(text: codec, style: AppText.strong),
              const TextSpan(text: ' · '),
              TextSpan(
                text: shareAudio ? 'Audio on' : 'Audio off',
                style: AppText.strong.copyWith(
                  color: shareAudio
                      ? themeState.primary
                      : themeState.textQuaternary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
