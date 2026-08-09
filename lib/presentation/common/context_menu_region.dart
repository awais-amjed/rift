import 'package:flutter/material.dart';

/// Lets menu content close the menu it lives in.
///
/// The menu is an [OverlayEntry], not a route, so `Navigator.pop` can't reach
/// it. Actions that navigate away — opening a DM — must dismiss; toggles like
/// mute deliberately leave it open so you can flip several.
class ContextMenuScope extends InheritedWidget {
  final VoidCallback dismiss;

  const ContextMenuScope({
    super.key,
    required this.dismiss,
    required super.child,
  });

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContextMenuScope>()?.dismiss;

  @override
  bool updateShouldNotify(ContextMenuScope oldWidget) => false;
}

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
              child: ContextMenuScope(
                dismiss: _dismiss,
                child: widget.contextMenu,
              ),
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

  const _PositionedMenu({required this.position, required this.child});

  @override
  Widget build(BuildContext context) {
    // Fills the overlay and places the menu inside it. The layout box itself
    // never answers a hit test, so a tap that misses the menu still reaches the
    // dismiss barrier underneath.
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: ContextMenuLayout(target: position),
        child: child,
      ),
    );
  }
}

/// Places a context menu against the point that opened it.
///
/// Menus are sized by their content — a member's menu is much taller than a
/// message's — so the position has to come from the child's *measured* size,
/// which is what [SingleChildLayoutDelegate] hands us. It used to be computed
/// against a guessed 320px: anchoring downward pinned the top edge to the
/// cursor and looked right, but flipping upward subtracted the guess instead of
/// the real height, leaving a band of empty space between a short menu and the
/// row it belonged to.
///
/// Flipping now anchors the opposite edge to the same point, so the menu hugs
/// the cursor whichever way it opens.
class ContextMenuLayout extends SingleChildLayoutDelegate {
  /// Where the menu was opened, in global coordinates.
  final Offset target;

  /// Kept clear of the screen edges, so a menu pushed against one still reads
  /// as floating above the app rather than welded to the side of it.
  final double margin;

  const ContextMenuLayout({required this.target, this.margin = 8});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Open down and to the right by default. Flip only when the menu genuinely
    // doesn't fit *and* the other side has more room — near the middle of the
    // screen, down beats a cramped up.
    final roomBelow = size.height - target.dy - margin;
    final roomAbove = target.dy - margin;
    final flipUp = childSize.height > roomBelow && roomAbove > roomBelow;

    final roomRight = size.width - target.dx - margin;
    final roomLeft = target.dx - margin;
    final flipLeft = childSize.width > roomRight && roomLeft > roomRight;

    return Offset(
      _clamp(
        flipLeft ? target.dx - childSize.width : target.dx,
        size.width - childSize.width - margin,
      ),
      _clamp(
        flipUp ? target.dy - childSize.height : target.dy,
        size.height - childSize.height - margin,
      ),
    );
  }

  /// Keeps [value] within `[margin, limit]`, preferring the near edge when the
  /// menu is larger than the space — a menu that can't fit should run off the
  /// far side, not be pushed off the near one.
  double _clamp(double value, double limit) {
    if (limit < margin) return margin;
    return value.clamp(margin, limit);
  }

  @override
  bool shouldRelayout(ContextMenuLayout oldDelegate) =>
      target != oldDelegate.target || margin != oldDelegate.margin;
}
