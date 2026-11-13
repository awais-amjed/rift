import 'package:material_ui/material_ui.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/media_colors.dart';
import '../../../../loading_dots.dart';

/// What sits in the middle of a video card that is not playing: the play
/// disc, the dots while it opens or waits for the file, or why it cannot
/// play.
class VideoMiddle extends StatelessWidget {
  final bool loading;
  final bool ended;

  /// Why it cannot play here, in words; null when it can.
  final String? problem;

  const VideoMiddle({
    super.key,
    required this.loading,
    required this.ended,
    this.problem,
  });

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    if (problem != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: MediaColors.onMediaSecondary,
              size: K.iconLarge,
            ),
            Text(
              problem,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(
                color: MediaColors.onMediaSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: MediaColors.panel,
        shape: BoxShape.circle,
      ),
      child: loading
          ? const Center(
              child: LoadingDots(color: MediaColors.onMedia, dotSize: 5),
            )
          : Icon(
              ended ? Icons.replay_rounded : Icons.play_arrow_rounded,
              color: MediaColors.onMedia,
              size: 30,
            ),
    );
  }
}
