import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import 'progress_track.dart';

/// The share of a download that is down, as a ring the size of the icon it
/// stands for.
///
/// Each report jumps rather than slides, for the reason [ProgressTrack]'s
/// do: a slide kept an animation running for the whole download, a frame on
/// every vsync, and the reports come several times a second anyway.
class DownloadRing extends StatelessWidget {
  final double fraction;
  final Color color;
  final double size;

  const DownloadRing({
    super.key,
    required this.fraction,
    required this.color,
    this.size = K.iconTiny,
  });

  @override
  Widget build(BuildContext context) {
    // Its own layer, so a report repaints the ring and not the row round it.
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size / 12),
          child: CircularProgressIndicator(
            value: fraction,
            strokeWidth: size * 0.14,
            color: color,
            backgroundColor: color.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
