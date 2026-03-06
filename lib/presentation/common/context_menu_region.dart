import 'package:flutter/material.dart';

class ContextMenuRegion extends StatefulWidget {
  final Widget child;
  final Widget contextMenu;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.contextMenu,
  });

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  OverlayEntry? _entry;

  void _show(Offset globalPosition) {
    _dismiss();

    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Full-screen barrier to dismiss on tap
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismiss,
                onSecondaryTap: _dismiss,
              ),
            ),
            _PositionedMenu(
              position: globalPosition,
              onDismiss: _dismiss,
              child: widget.contextMenu,
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_entry!);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _show(details.globalPosition),
      onLongPressStart: (details) => _show(details.globalPosition),
      child: widget.child,
    );
  }
}

class _PositionedMenu extends StatelessWidget {
  final Offset position;
  final Widget child;
  final VoidCallback onDismiss;

  const _PositionedMenu({
    required this.position,
    required this.child,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const menuWidth = 224.0;
    const menuMaxHeight = 320.0;

    final left = (position.dx + menuWidth > size.width)
        ? size.width - menuWidth - 8
        : position.dx;
    final top = (position.dy + menuMaxHeight > size.height)
        ? position.dy - menuMaxHeight
        : position.dy;

    return Positioned(left: left, top: top, child: child);
  }
}
