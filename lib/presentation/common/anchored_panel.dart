import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';

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
/// below the anchor.
Future<T?> showAnchoredPanel<T>({
  required BuildContext anchor,
  required double width,
  required Widget child,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchor, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (box == null || overlay == null || !box.hasSize) {
    return Future.value();
  }
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;

  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.state,
    pageBuilder: (context, _, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _BelowAnchor(anchor: rect, width: width),
          child: child,
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
            begin: const Offset(0, -0.015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Under the anchor, right edges aligned, kept inside the window.
class _BelowAnchor extends SingleChildLayoutDelegate {
  final Rect anchor;
  final double width;

  /// Between the anchor and the panel, and between the panel and the window.
  static const double _gap = 6;
  static const double _margin = 12;

  /// Below this the panel stops fitting under the anchor and simply scrolls.
  static const double _minHeight = 200;

  const _BelowAnchor({required this.anchor, required this.width});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(width, constraints.maxWidth - _margin * 2);
    final below = constraints.maxHeight - anchor.bottom - _gap - _margin;
    return BoxConstraints(
      minWidth: maxWidth,
      maxWidth: maxWidth,
      maxHeight: math.max(_minHeight, below),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (anchor.right - childSize.width)
        .clamp(
          _margin,
          math.max(_margin, size.width - childSize.width - _margin),
        )
        .toDouble();
    final top = math.min(
      anchor.bottom + _gap,
      math.max(_margin, size.height - childSize.height - _margin),
    );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_BelowAnchor old) =>
      old.anchor != anchor || old.width != width;
}
