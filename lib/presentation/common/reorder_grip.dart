import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Where a drag to reorder a list starts, chosen by the pointer that pressed.
///
/// A mouse lifts the row at once, as Flutter's own
/// [ReorderableDragStartListener] does for every pointer. A finger must not:
/// a list is scrolled by swiping over its rows, so on a touchscreen in the
/// wide layout every swipe through the channels picked one up. A finger
/// lifts the row after a hold when [touchAfterHold] is set, and never
/// otherwise, which is for rows whose hold opens their menu.
class ReorderGrip extends StatelessWidget {
  final int index;
  final bool touchAfterHold;
  final Widget child;

  const ReorderGrip({
    super.key,
    required this.index,
    this.touchAfterHold = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _start(context, event),
      child: child,
    );
  }

  void _start(BuildContext context, PointerDownEvent event) {
    final MultiDragGestureRecognizer recognizer;
    if (event.kind == PointerDeviceKind.mouse) {
      recognizer = ImmediateMultiDragGestureRecognizer(debugOwner: this);
    } else if (touchAfterHold) {
      recognizer = DelayedMultiDragGestureRecognizer(debugOwner: this);
    } else {
      return;
    }
    SliverReorderableList.maybeOf(context)?.startItemDragReorder(
      index: index,
      event: event,
      recognizer: recognizer
        ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
    );
  }
}
