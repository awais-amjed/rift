import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/stream_pip_corner.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/media_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../participants_grid/participants_tile/participant_name_badge.dart';
import '../../participants_grid/participants_tile/pip_resize_grip.dart';
import '../../participants_grid/participants_tile/stream_corner_button.dart';
import '../../participants_grid/participants_tile/watched_stream_picture.dart';

/// The floating stream itself: the picture, and on hover whose it is, which
/// is pressed to go back to the call, a button to put it away, and the resize
/// grip.
///
/// The name and buttons run along the edge by its corner, the grip sits on
/// the edge facing into the pane, so the two never meet.
class CallPipCard extends StatefulWidget {
  final String identity;

  /// The corner it rests in.
  final StreamPipCorner corner;

  /// Being dragged or resized: the controls stay while it is.
  final bool held;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final GestureDragUpdateCallback onResize;
  final VoidCallback onResizeEnd;

  const CallPipCard({
    super.key,
    required this.identity,
    required this.corner,
    required this.held,
    required this.onOpen,
    required this.onDismiss,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.onResizeEnd,
  });

  @override
  State<CallPipCard> createState() => _CallPipCardState();
}

class _CallPipCardState extends State<CallPipCard> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    final controls = _hovered || widget.held;
    return MouseRegion(
      cursor: _dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Taken here, so a press falls through to nothing under it.
        onTap: () {},
        onPanStart: (_) {
          setState(() => _dragging = true);
          widget.onDragStart();
        },
        onPanUpdate: (d) => widget.onDrag(d.delta),
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: AppShadows.popover,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: theme.borderElevated),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: MediaColors.videoGround,
                    child: WatchedStreamPicture(
                      identity: widget.identity,
                      frame: (picture) => picture,
                    ),
                  ),
                  Align(
                    alignment: widget.corner.isTop
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: _fading(controls, _controls()),
                  ),
                  PipResizeGrip(
                    corner: widget.corner,
                    visible: controls,
                    onResize: widget.onResize,
                    onEnd: widget.onResizeEnd,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag() {
    setState(() => _dragging = false);
    widget.onDragEnd();
  }

  static Widget _fading(bool visible, Widget child) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: AppMotion.state,
    curve: AppMotion.settle,
    child: IgnorePointer(ignoring: !visible, child: child),
  );

  Widget _controls() {
    final name = context.select<AppCubit, String>(
      (c) =>
          c.state.participants
              .where((p) => p.identity == widget.identity)
              .firstOrNull
              ?.name ??
          '',
    );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            // As tall as what it holds: an Align takes all the height it is
            // offered, which stood the row in the middle of the picture.
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              // Whose stream it is, and the way back to it: the one thing
              // here somebody would think to press.
              child: Tooltip(
                message: 'Back to the call',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onOpen,
                    child: ParticipantNameBadge(
                      name: name.isEmpty ? 'Back to the call' : name,
                      isMicEnabled: true,
                      isMuted: false,
                      isScreenshare: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          StreamCornerButton(
            icon: Icons.close_rounded,
            tooltip: 'Hide',
            onTap: widget.onDismiss,
          ),
        ],
      ),
    );
  }
}
