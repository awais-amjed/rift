import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/stream_pip_corner.dart';

/// What resizes a floating picture: the two edges facing away from the corner
/// it rests in, which are the ones that move, and the corner between them.
/// Goes in the picture's [Stack], filling it.
///
/// Like a window's border: nothing is drawn, the edges are there whether or
/// not the picture's controls are showing, and the pointer turns to the
/// resize arrows over them. An edge passes on only its own direction, so a
/// side resizes by the pointer going across and a top or bottom by it going
/// up or down; the corner passes on both.
///
/// Shared by the sharer's camera over a stream and a stream floating over a
/// chat, so the two resize alike.
class PipResizeGrip extends StatelessWidget {
  /// The corner the picture rests in, which stays put.
  final StreamPipCorner corner;
  final GestureDragUpdateCallback onResize;
  final VoidCallback onEnd;

  const PipResizeGrip({
    super.key,
    required this.corner,
    required this.onResize,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    const edge = K.pipResizeEdge;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The side facing in.
        Positioned(
          top: 0,
          bottom: 0,
          left: corner.isLeft ? null : 0,
          right: corner.isLeft ? 0 : null,
          width: edge,
          child: _handle(
            SystemMouseCursors.resizeLeftRight,
            only: (d) => Offset(d.dx, 0),
          ),
        ),
        // The top or bottom facing in.
        Positioned(
          left: 0,
          right: 0,
          top: corner.isTop ? null : 0,
          bottom: corner.isTop ? 0 : null,
          height: edge,
          child: _handle(
            SystemMouseCursors.resizeUpDown,
            only: (d) => Offset(0, d.dy),
          ),
        ),
        // The corner between them, over both.
        Positioned(
          left: corner.isLeft ? null : 0,
          right: corner.isLeft ? 0 : null,
          top: corner.isTop ? null : 0,
          bottom: corner.isTop ? 0 : null,
          width: K.pipResizeCorner,
          height: K.pipResizeCorner,
          child: _handle(
            corner.isTop == corner.isLeft
                ? SystemMouseCursors.resizeUpLeftDownRight
                : SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
      ],
    );
  }

  /// A place to press that resizes, passing on the part of each move [only]
  /// keeps (all of it when absent).
  Widget _handle(MouseCursor cursor, {Offset Function(Offset delta)? only}) =>
      MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          // Taken over the whole strip, with nothing painted on it.
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => onResize(
            only == null
                ? d
                : DragUpdateDetails(
                    sourceTimeStamp: d.sourceTimeStamp,
                    delta: only(d.delta),
                    globalPosition: d.globalPosition,
                    localPosition: d.localPosition,
                  ),
          ),
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
        ),
      );
}
