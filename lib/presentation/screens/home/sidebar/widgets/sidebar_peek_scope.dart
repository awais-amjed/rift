import 'package:flutter/widgets.dart';

/// Marks the sidebar contents that [SidebarPeek] floats over the content.
///
/// The one thing that reads differently there is the header's chevron.
/// Docked it hides the sidebar; in a peek the sidebar is already hidden, so
/// the same button keeps it open instead.
class SidebarPeekScope extends InheritedWidget {
  const SidebarPeekScope({super.key, required super.child});

  static bool isPeek(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarPeekScope>() != null;

  @override
  bool updateShouldNotify(SidebarPeekScope oldWidget) => false;
}
