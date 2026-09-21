import 'package:flutter/widgets.dart';

/// Hears about every context menu opened from somewhere below it.
///
/// A menu is an [OverlayEntry] drawn above the whole app, so the pointer
/// going to one looks exactly like the pointer leaving whatever opened it.
/// Anything that hides itself when the pointer leaves — the sidebar peek —
/// needs to know a menu of its own is still up, or it slides away and takes
/// the row the menu belongs to with it.
class ContextMenuWatcher extends InheritedWidget {
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  const ContextMenuWatcher({
    super.key,
    required this.onOpened,
    required this.onClosed,
    required super.child,
  });

  /// Read without depending: it is only called while a menu is being opened.
  static ContextMenuWatcher? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ContextMenuWatcher>();

  @override
  bool updateShouldNotify(ContextMenuWatcher oldWidget) => false;
}
