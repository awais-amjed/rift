import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_motion.dart';

/// The grab strip between the sidebar and the content.
///
/// It sits in the gutter that was already there, so the sidebar became
/// resizable without taking a pixel from either side. Invisible until you're
/// on it — a permanent divider would draw a line down a layout whose whole
/// idea is separate floating panels.
class SidebarResizeHandle extends StatefulWidget {
  /// Pointer moved by [delta] logical pixels horizontally.
  final ValueChanged<double> onDrag;

  /// The drag finished — the moment to persist, rather than every frame.
  final VoidCallback onDragEnd;

  /// Double-click, which puts the sidebar back to its default width.
  final VoidCallback onReset;

  const SidebarResizeHandle({
    super.key,
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Opaque: the strip is mostly empty space, and a drag has to start
        // anywhere on it rather than only on the pixels that are painted.
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        child: SizedBox(
          width: K.sidebarResizeHandleWidth,
          child: Center(
            child: AnimatedOpacity(
              duration: AppMotion.react,
              opacity: active ? 1 : 0,
              child: Container(
                width: 3,
                height: 44,
                decoration: BoxDecoration(
                  color: context.watch<ThemeCubit>().state.primary.withValues(
                    alpha: _dragging ? 0.9 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
