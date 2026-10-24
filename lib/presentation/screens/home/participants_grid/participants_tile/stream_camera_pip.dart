import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/stream_pip_corner.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/theme_context.dart';
import 'decrypted_video.dart';
import 'stream_glass.dart';

/// The sharer's camera, floating in a corner of the stream it is watched
/// over: with the stream filling the stage, nothing else shows their face.
///
/// Dragged, it follows the pointer, and let go it settles in the corner of
/// the quarter it was dropped in. The grip on its inner corner makes it
/// larger or smaller, from a thumbnail to under half the stream. It stays up
/// while the stream's other overlays fade — it is a picture, not a control —
/// and is put away with the camera button beside the stream's others. Goes
/// inside the stage's [Stack].
class StreamCameraPip extends StatefulWidget {
  final VideoTrack track;
  final StreamPipCorner corner;

  /// Its width as a share of the stage's ([sizeFor]).
  final double scale;

  /// The stage it floats over.
  final Size stage;

  /// How far it keeps from each edge: clear of the badges and buttons along
  /// the foot, and of a bar floating over the head.
  final EdgeInsets margin;
  final ValueChanged<StreamPipCorner> onCorner;

  /// Told the new [scale] once a resize is let go.
  final ValueChanged<double> onScale;

  /// Whether the resize grip shows: with the stream's other overlays, which
  /// pointer movement brings back.
  final bool showGrip;

  const StreamCameraPip({
    super.key,
    required this.track,
    required this.corner,
    required this.scale,
    required this.stage,
    required this.margin,
    required this.onCorner,
    required this.onScale,
    required this.showGrip,
  });

  static const _aspect = 16 / 9;

  /// Smaller than this and a face is not much more than a colour.
  static const _minWidth = 120.0;

  /// The most of the stage it may cover, across and down: past this it is
  /// no longer a picture in a picture.
  static const _maxShare = 0.45;

  /// The widths it may take on [stage].
  static (double, double) _widths(Size stage) {
    final most = (stage.width * _maxShare).clamp(
      0.0,
      stage.height * _maxShare * _aspect,
    );
    return (most < _minWidth ? most : _minWidth, most);
  }

  /// Its size at [scale] of [stage]'s width, within [_widths].
  static Size sizeFor(Size stage, double scale) {
    final (least, most) = _widths(stage);
    final w = (stage.width * scale).clamp(least, most);
    return Size(w, w / _aspect);
  }

  @override
  State<StreamCameraPip> createState() => _StreamCameraPipState();
}

class _StreamCameraPipState extends State<StreamCameraPip> {
  /// Where its top left is while it is being dragged.
  Offset? _drag;

  /// Its width while the grip is being dragged.
  double? _resizing;

  Size get _size => switch (_resizing) {
    final w? => Size(w, w / StreamCameraPip._aspect),
    null => StreamCameraPip.sizeFor(widget.stage, widget.scale),
  };

  Offset _restingAt(StreamPipCorner corner) {
    final m = widget.margin;
    return Offset(
      corner.isLeft ? m.left : widget.stage.width - m.right - _size.width,
      corner.isTop ? m.top : widget.stage.height - m.bottom - _size.height,
    );
  }

  /// Kept on the stage, however far the pointer goes.
  Offset _clamp(Offset at) => Offset(
    at.dx.clamp(0, widget.stage.width - _size.width),
    at.dy.clamp(0, widget.stage.height - _size.height),
  );

  void _drop() {
    final at = _drag;
    if (at == null) return;
    widget.onCorner(
      StreamPipCorner.nearest(
        at.dx + _size.width / 2,
        at.dy + _size.height / 2,
        widget.stage.width,
        widget.stage.height,
      ),
    );
    setState(() => _drag = null);
  }

  /// The grip grows it away from its corner, which stays put: whichever way
  /// the pointer moved further, across or down.
  void _resize(DragUpdateDetails details) {
    final across = widget.corner.isLeft ? details.delta.dx : -details.delta.dx;
    final down =
        (widget.corner.isTop ? details.delta.dy : -details.delta.dy) *
        StreamCameraPip._aspect;
    final grow = across.abs() >= down.abs() ? across : down;
    final (least, most) = StreamCameraPip._widths(widget.stage);
    setState(() => _resizing = (_size.width + grow).clamp(least, most));
  }

  void _endResize() {
    final w = _resizing;
    if (w == null) return;
    widget.onScale(w / widget.stage.width);
    setState(() => _resizing = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final size = _size;
    final at = _drag ?? _restingAt(widget.corner);
    final radius = BorderRadius.circular(K.radiusCard);
    final held = _drag != null || _resizing != null;
    return AnimatedPositioned(
      // Under the pointer while dragged or resized; into its corner once let
      // go.
      duration: held ? Duration.zero : AppMotion.state,
      curve: AppMotion.settle,
      left: at.dx,
      top: at.dy,
      width: size.width,
      height: size.height,
      child: MouseRegion(
        cursor: _drag != null
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          // Taken here, or a tap fell through to the stage and put the
          // stream back among everyone else.
          onTap: () {},
          onPanStart: (_) => setState(() => _drag = at),
          onPanUpdate: (details) =>
              setState(() => _drag = _clamp(_drag! + details.delta)),
          onPanEnd: (_) => _drop(),
          onPanCancel: _drop,
          child: Stack(
            fit: StackFit.expand,
            children: [_picture(theme, radius), _grip()],
          ),
        ),
      ),
    );
  }

  Widget _picture(ThemeState theme, BorderRadius radius) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: radius,
      boxShadow: AppShadows.popover,
    ),
    position: DecorationPosition.background,
    child: ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: theme.borderElevated),
        ),
        child: DecryptedVideo(
          track: widget.track,
          child: VideoTrackRenderer(widget.track, fit: VideoViewFit.cover),
        ),
      ),
    ),
  );

  /// On the corner facing into the stream, the one that moves.
  Widget _grip() {
    final corner = widget.corner;
    final visible = widget.showGrip || _resizing != null;
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
              onPanUpdate: _resize,
              onPanEnd: (_) => _endResize(),
              onPanCancel: _endResize,
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
