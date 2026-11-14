import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/stream_pip_corner.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/theme_context.dart';
import 'stream_glass.dart';

/// The grip that resizes a floating picture, on the corner facing away from
/// the one it rests in: the corner that moves. Goes in the picture's [Stack].
///
/// Shared by the sharer's camera over a stream and a stream floating over a
/// chat, so the two resize alike.
class PipResizeGrip extends StatelessWidget {
  /// The corner the picture rests in, which stays put.
  final StreamPipCorner corner;
  final bool visible;
  final GestureDragUpdateCallback onResize;
  final VoidCallback onEnd;

  const PipResizeGrip({
    super.key,
    required this.corner,
    required this.visible,
    required this.onResize,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    // The arrow runs from the grip to the corner that stays put.
    final diagonal = corner.isTop == corner.isLeft;
    return Align(
      alignment: Alignment(corner.isLeft ? 1 : -1, corner.isTop ? 1 : -1),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.enter,
        child: IgnorePointer(
          ignoring: !visible,
          child: MouseRegion(
            cursor: diagonal
                ? SystemMouseCursors.resizeUpLeftDownRight
                : SystemMouseCursors.resizeUpRightDownLeft,
            child: GestureDetector(
              onPanUpdate: onResize,
              onPanEnd: (_) => onEnd(),
              onPanCancel: onEnd,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: StreamGlass(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: RotatedBox(
                      // open_in_full points up right and down left.
                      quarterTurns: diagonal ? 1 : 0,
                      child: Icon(
                        Icons.open_in_full_rounded,
                        size: K.iconInline,
                        color: context.theme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
