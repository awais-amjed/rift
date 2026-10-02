import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';

/// Said over a stream whose shared window has been minimised.
///
/// Windows gives a capturer nothing for a minimised window, so viewers keep
/// the last frame. Without this the picture just stops, which reads as the
/// call breaking rather than as the sharer having put the window away.
class SharePausedNotice extends StatelessWidget {
  const SharePausedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MediaColors.panel,
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const Icon(
              Icons.pause_rounded,
              size: K.iconRow,
              color: MediaColors.onMedia,
            ),
            Flexible(
              child: Text(
                'Paused — the shared window is minimised',
                style: AppText.secondary.copyWith(color: MediaColors.onMedia),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
