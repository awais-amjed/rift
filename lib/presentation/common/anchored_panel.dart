import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_motion.dart';
import 'server_scope.dart';
import 'show_custom_dialog.dart';

/// Open [child] as a panel hanging from [anchor] — under it, its right edge
/// on the anchor's right edge — the way a header button's list drops down.
///
/// For something bigger than a menu and smaller than a dialog: a list the
/// reader looks through and leaves, which a dialog in the middle of the
/// window would put on top of the very conversation it is about. A press
/// outside or Escape closes it.
///
/// [width] is what the panel asks for; a window narrower than that gets the
/// window less a margin. Its height is whatever [child] needs, up to what fits
/// below the anchor — or above it, with [above], for a button at the foot of
/// the window, such as one in the call's control bar. [alignLeft] lines up
/// the left edges instead, for an anchor near the window's left side, where
/// a panel right-aligned to it would be pushed against the edge.
///
/// The anchor is measured again whenever the window changes size, so a panel
/// hanging over the dock stays on its button rather than where the button was.
Future<T?> showAnchoredPanel<T>({
  required BuildContext anchor,
  required double width,
  required Widget child,
  bool above = false,
  bool alignLeft = false,
}) {
  final rect = _rectOf(anchor);
  if (rect == null) return Future.value();
  final panel = ServerScope.carry(anchor, child);

  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.state,
    // A scope that answers Escape itself — see [showCustomDialog] for why a
    // shortcut inside the route stops hearing it once an Unpin disables.
    pageBuilder: (context, _, _) => FocusScope(
      autofocus: true,
      onKeyEvent: (_, event) => closeOnEscape(context, event),
      child: _Placement(
        anchor: anchor,
        first: rect,
        builder: (rect) => CustomSingleChildLayout(
          delegate: _ByAnchor(
            anchor: rect,
            width: width,
            above: above,
            alignLeft: alignLeft,
          ),
          child: panel,
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.arrive,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, above ? 0.015 : -0.015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Where [anchor] is in the root overlay, or null once it is gone.
Rect? _rectOf(BuildContext anchor) {
  if (!anchor.mounted) return null;
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.maybeOf(anchor, rootOverlay: true)?.context.findRenderObject()
          as RenderBox?;
  if (box == null || overlay == null || !box.hasSize || !box.attached) {
    return null;
  }
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// The anchor's place, measured again after each change of the window's size.
///
/// After the frame, since the anchor is laid out in the same frame the panel
/// is built in, and measured during it would still be where it was. An anchor
/// gone by then leaves the panel where it last was.
class _Placement extends StatefulWidget {
  final BuildContext anchor;
  final Rect first;
  final Widget Function(Rect anchor) builder;

  const _Placement({
    required this.anchor,
    required this.first,
    required this.builder,
  });

  @override
  State<_Placement> createState() => _PlacementState();
}

class _PlacementState extends State<_Placement> {
  late Rect _rect;
  Size? _window;

  @override
  void initState() {
    super.initState();
    _rect = widget.first;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = MediaQuery.sizeOf(context);
    if (_window != null && _window != window) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect = _rectOf(widget.anchor);
        if (rect != null && rect != _rect) setState(() => _rect = rect);
      });
    }
    _window = window;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_rect);
}

/// Under the anchor (or over it, [above]), right edges aligned ([alignLeft]:
/// left ones), kept inside the window.
class _ByAnchor extends SingleChildLayoutDelegate {
  final Rect anchor;
  final double width;
  final bool above;
  final bool alignLeft;

  /// Between the anchor and the panel, and between the panel and the window.
  static const double _gap = 6;
  static const double _margin = 12;

  /// Below this the panel stops fitting under the anchor and simply scrolls.
  static const double _minHeight = 200;

  const _ByAnchor({
    required this.anchor,
    required this.width,
    required this.above,
    required this.alignLeft,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(width, constraints.maxWidth - _margin * 2);
    final room = above
        ? anchor.top - _gap - _margin
        : constraints.maxHeight - anchor.bottom - _gap - _margin;
    return BoxConstraints(
      minWidth: maxWidth,
      maxWidth: maxWidth,
      maxHeight: math.max(_minHeight, room),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (alignLeft ? anchor.left : anchor.right - childSize.width)
        .clamp(
          _margin,
          math.max(_margin, size.width - childSize.width - _margin),
        )
        .toDouble();
    final top = above
        ? math.max(_margin, anchor.top - _gap - childSize.height)
        : math.min(
            anchor.bottom + _gap,
            math.max(_margin, size.height - childSize.height - _margin),
          );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ByAnchor old) =>
      old.anchor != anchor ||
      old.width != width ||
      old.above != above ||
      old.alignLeft != alignLeft;
}
