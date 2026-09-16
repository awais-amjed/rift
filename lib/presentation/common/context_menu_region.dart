import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/services/host_platform.dart';
import '../responsive/shell_scope.dart';
import 'context_menu/context_menu_sheet.dart';

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
  final ContextMenuOverlay _overlay = ContextMenuOverlay();

  @override
  void dispose() {
    _overlay.dismiss();
    super.dispose();
  }

  /// A long press is the touch equivalent of a right-click, and the only
  /// signal that it has registered is the buzz — the menu opens *after* the
  /// press is held, so without it the finger spends half a second on a screen
  /// that appears to be ignoring it. Mobile only: a desktop has no vibrator,
  /// and long-press there is a fallback for a right-click that already worked.
  void _openByTouch(Offset position) {
    if (HostPlatform.isMobile) HapticFeedback.mediumImpact();
    _overlay.show(context, widget.contextMenu, position);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _overlay.show(context, widget.contextMenu, details.globalPosition),
      onLongPressStart: (details) => _openByTouch(details.globalPosition),
      child: widget.child,
    );
  }
}

/// One open context menu, owned by whatever opened it.
///
/// Shared by the right-click region and the overflow button, so a menu opened
/// either way is the same object: placed against the same point, dismissed by
/// the same barrier, and shown as a bottom sheet on a phone. The owner calls
/// [dismiss] when it goes away, so a menu never outlives the row it belongs to.
class ContextMenuOverlay {
  OverlayEntry? _entry;

  bool get isOpen => _entry != null;

  void show(BuildContext context, Widget menu, Offset globalPosition) {
    dismiss();

    // A phone gets the same menu as a sheet: there is no pointer to hang a
    // panel off, and a thumb needs rows the width of the screen.
    if (context.layoutMode.isCompact) {
      showContextMenuSheet(context, menu);
      return;
    }

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Full-screen barrier to dismiss on tap
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: dismiss,
              onSecondaryTap: dismiss,
            ),
          ),
          _PositionedMenu(
            position: globalPosition,
            child: ContextMenuScope(dismiss: dismiss, child: menu),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void dismiss() {
    _entry?.remove();
    _entry = null;
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
