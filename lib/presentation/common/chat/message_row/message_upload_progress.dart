import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// How far a sending message's files have got, under its text, while a big
/// one uploads. Gone once the message is sent, which replaces the row.
class MessageUploadProgress extends StatelessWidget {
  static const double _width = 270;
  static const double _track = 4;

  /// 0 to 1.
  final double progress;

  const MessageUploadProgress({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final shown = progress.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(K.radiusPill),
              child: Container(
                height: _track,
                color: theme.bgTertiary,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: shown),
                  duration: AppMotion.state,
                  curve: AppMotion.settle,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value,
                    child: Container(color: theme.primary),
                  ),
                ),
              ),
            ),
            Text(
              'Uploading · ${(shown * 100).floor()}%',
              style: AppText.meta.copyWith(color: theme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
