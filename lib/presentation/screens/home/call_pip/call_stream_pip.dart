import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/stream_pip_corner.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../theme/app_motion.dart';
import '../calls/show_the_call.dart';
import 'widgets/call_pip_card.dart';

/// A stream this device is watching, floating in a corner of the centre pane
/// while the call itself is not on screen: a chat or a DM opened over it.
///
/// Before this the stream simply went away with the stage, its sound playing
/// on with nothing to look at. It behaves like the sharer's camera over a
/// stream: dragged, it settles in the corner of the quarter it was dropped
/// in, and the grip on its inner corner resizes it; both are kept for next
/// time. A press on it does nothing, since it is so easily hit on the way to
/// the chat under it: its own button goes back to the call, and its ✕ puts it
/// away until the call is next looked at, without stopping the stream.
///
/// Fills the pane it is put over and takes no pointer outside the card.
class CallStreamPip extends StatefulWidget {
  const CallStreamPip({super.key});

  @override
  State<CallStreamPip> createState() => _CallStreamPipState();
}

class _CallStreamPipState extends State<CallStreamPip> {
  static const _aspect = 16 / 9;

  /// The stream whose card was put away, until the stage shows again.
  String? _dismissed;

  /// Where its top left is while it is being dragged.
  Offset? _drag;

  /// Its width while the grip is being dragged.
  double? _resizing;

  @override
  Widget build(BuildContext context) {
    final stageShown = context.select<AppCubit, bool>(
      (c) => c.state.callStageShown,
    );
    final corner = context.select<AppCubit, StreamPipCorner>(
      (c) => c.state.callPipCorner,
    );
    final savedWidth = context.select<AppCubit, double>(
      (c) => c.state.callPipWidth,
    );
    // The stream watched last, while the call is up. A set keeps the order
    // they were added in.
    final watched = context.select<LiveKitCubit, String?>((c) {
      final lk = c.state;
      if (lk.connectionState != LiveKitConnectionState.connected) return null;
      return lk.subscribedScreenshares.lastOrNull;
    });
    // Looking at the call again is what brings a put-away card back.
    if (stageShown) _dismissed = null;
    final identity = stageShown || watched == _dismissed ? null : watched;

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final (least, most) = _widths(area);
        final width = (_resizing ?? savedWidth).clamp(least, most);
        final size = Size(width, width / _aspect);
        final shown = identity != null && most >= K.callPipMinWidth * 0.75;
        final at = _drag ?? _restingAt(corner, area, size);
        final held = _drag != null || _resizing != null;
        return Stack(
          children: [
            AnimatedPositioned(
              // Under the pointer while dragged or resized; into its corner
              // once let go.
              duration: held ? Duration.zero : AppMotion.state,
              curve: AppMotion.settle,
              left: at.dx,
              top: at.dy,
              width: size.width,
              height: size.height,
              child: AnimatedSwitcher(
                duration: AppMotion.enter,
                switchInCurve: AppMotion.arrive,
                switchOutCurve: AppMotion.arrive,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: shown
                    ? CallPipCard(
                        key: ValueKey(identity),
                        identity: identity,
                        corner: corner,
                        held: held,
                        onOpen: () => showTheCall(
                          context,
                          context.read<LiveKitCubit>().state,
                        ),
                        onDismiss: () => setState(() => _dismissed = identity),
                        onDragStart: () => setState(() => _drag = at),
                        onDrag: (delta) => setState(
                          () => _drag = _clamp(_drag! + delta, area, size),
                        ),
                        onDragEnd: () => _drop(area, size),
                        onResize: (d) => _resize(d, corner, width, area),
                        onResizeEnd: _endResize,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The widths it may take in [area]: what fits between the pane's header
  /// and composer, and between its sides.
  static (double, double) _widths(Size area) {
    final across = area.width - 2 * K.callPipSideMargin;
    final down =
        (area.height - K.callPipTopClearance - K.callPipBottomClearance) *
        _aspect;
    final most = across < down ? across : down;
    return (most < K.callPipMinWidth ? most : K.callPipMinWidth, most);
  }

  static Offset _restingAt(StreamPipCorner corner, Size area, Size size) =>
      Offset(
        corner.isLeft
            ? K.callPipSideMargin
            : area.width - K.callPipSideMargin - size.width,
        corner.isTop
            ? K.callPipTopClearance
            : area.height - K.callPipBottomClearance - size.height,
      );

  /// Kept in the pane, however far the pointer goes.
  static Offset _clamp(Offset at, Size area, Size size) => Offset(
    at.dx.clamp(0, area.width - size.width),
    at.dy.clamp(0, area.height - size.height),
  );

  void _drop(Size area, Size size) {
    final at = _drag;
    if (at == null) return;
    context.read<AppCubit>().setCallPipCorner(
      StreamPipCorner.nearest(
        at.dx + size.width / 2,
        at.dy + size.height / 2,
        area.width,
        area.height,
      ),
    );
    setState(() => _drag = null);
  }

  /// The grip grows it away from its corner, which stays put: whichever way
  /// the pointer moved further, across or down.
  void _resize(
    DragUpdateDetails details,
    StreamPipCorner corner,
    double width,
    Size area,
  ) {
    final across = corner.isLeft ? details.delta.dx : -details.delta.dx;
    final down =
        (corner.isTop ? details.delta.dy : -details.delta.dy) * _aspect;
    final grow = across.abs() >= down.abs() ? across : down;
    final (least, most) = _widths(area);
    setState(() => _resizing = (width + grow).clamp(least, most));
  }

  void _endResize() {
    final w = _resizing;
    if (w == null) return;
    context.read<AppCubit>().setCallPipWidth(w);
    setState(() => _resizing = null);
  }
}
