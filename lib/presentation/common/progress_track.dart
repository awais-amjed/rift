import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import '../theme/theme_context.dart';

/// A thin bar filling with the accent as something moves along: a file
/// uploading under its message, an update downloading in Settings.
///
/// Each report jumps rather than slides. A slide is an animation, a frame on
/// every vsync, and a download reports often enough to keep one running
/// throughout: 165 frames a second on a 165 Hz laptop for a 4 px bar. The
/// reports come fast enough to read as movement anyway.
class ProgressTrack extends StatelessWidget {
  static const double _height = 4;

  /// 0 to 1.
  final double progress;

  const ProgressTrack({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // Its own layer, so a report repaints the bar and not the page round it.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(K.radiusPill),
        child: Container(
          height: _height,
          color: theme.bgTertiary,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: theme.primary),
          ),
        ),
      ),
    );
  }
}
