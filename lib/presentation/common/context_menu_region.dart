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

  /// Runs just before the menu opens.
  ///
  /// For a menu whose items act on app-wide *current* state rather than on
  /// something they were handed, this is where the right-click makes that state
  /// agree with what was clicked. The rail's chips are the case: their dialogs
  /// and every API call under them resolve `ServerCubit`'s **selected** server,
  /// so without this the menu opens on one server and acts on another.
  final VoidCallback? onOpen;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.contextMenu,
    this.onOpen,
  });

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  OverlayEntry? _entry;

  void _show(Offset globalPosition) {
    _dismiss();
    widget.onOpen?.call();

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
        delegate: ContextMenuLayout.atPoint(position),
        child: child,
      ),
    );
  }
}

/// Places a menu against the thing that opened it.
///
/// Menus are sized by their content — a member's menu is much taller than a
/// message's — so the position has to come from the child's *measured* size,
/// which is what [SingleChildLayoutDelegate] hands us. It used to be computed
/// against a guessed 320px: anchoring downward pinned the top edge to the
/// cursor and looked right, but flipping upward subtracted the guess instead of
/// the real height, leaving a band of empty space between a short menu and the
/// row it belonged to.
///
/// The anchor is a **rectangle**, because flipping has to know both of its
/// edges. A right-click anchors to a point ([ContextMenuLayout.atPoint]), where
/// the two coincide and flipping simply pivots about the cursor. A submenu
/// anchors to the row that opened it: it opens from the row's right edge, and
/// when it flips it opens from the row's *left* edge — the parent panel's outer
/// edge — so it lands beside the menu instead of on top of it.
class ContextMenuLayout extends SingleChildLayoutDelegate {
  /// What the menu hangs off, in overlay coordinates. The menu prefers to sit
  /// past [Rect.right] and below [Rect.top]; flipped, it sits before
  /// [Rect.left] and above [Rect.bottom].
  final Rect anchor;

  /// Kept clear of the screen edges, so a menu pushed against one still reads
  /// as floating above the app rather than welded to the side of it.
  final double margin;

  const ContextMenuLayout({required this.anchor, this.margin = 8});

  /// Anchors to a single point — a cursor. Flipping pivots about it, so the
  /// menu hugs the cursor whichever way it opens.
  ContextMenuLayout.atPoint(Offset target, {this.margin = 8})
    : anchor = Rect.fromLTWH(target.dx, target.dy, 0, 0);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Open down and to the right by default. Flip only when the menu genuinely
    // doesn't fit *and* the other side has more room — near the middle of the
    // screen, down beats a cramped up.
    final roomBelow = size.height - anchor.top - margin;
    final roomAbove = anchor.bottom - margin;
    final flipUp = childSize.height > roomBelow && roomAbove > roomBelow;

    final roomRight = size.width - anchor.right - margin;
    final roomLeft = anchor.left - margin;
    final flipLeft = childSize.width > roomRight && roomLeft > roomRight;

    return Offset(
      _clamp(
        flipLeft ? anchor.left - childSize.width : anchor.right,
        size.width - childSize.width - margin,
      ),
      _clamp(
        flipUp ? anchor.bottom - childSize.height : anchor.top,
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
      anchor != oldDelegate.anchor || margin != oldDelegate.margin;
}
