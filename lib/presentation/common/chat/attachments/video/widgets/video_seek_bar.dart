import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/media_colors.dart';

/// The strip along a playing video's foot: where it is, as a bar you can
/// press or drag to move it, and the time beside it.
class VideoSeekBar extends StatelessWidget {
  final Duration position;
  final Duration length;
  final ValueChanged<Duration> onSeek;

  const VideoSeekBar({
    super.key,
    required this.position,
    required this.length,
    required this.onSeek,
  });

  static String clock(Duration d) {
    final m = d.inMinutes.toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _seekAt(double dx, double width) {
    if (width <= 0 || length == Duration.zero) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    onSeek(length * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final total = length.inMilliseconds;
    final done = total == 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      color: MediaColors.toolbar,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _seekAt(d.localPosition.dx, constraints.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _seekAt(d.localPosition.dx, constraints.maxWidth),
                  child: Padding(
                    // A taller target than the bar it draws.
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(K.radiusPill),
                      child: LinearProgressIndicator(
                        value: done,
                        minHeight: 4,
                        backgroundColor: MediaColors.onMediaQuaternary,
                        color: MediaColors.onMedia,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            '${clock(position)} / ${clock(length)}',
            // Ticks while playing, so it must not change width.
            style: AppText.figure.copyWith(color: MediaColors.onMedia),
          ),
        ],
      ),
    );
  }
}
