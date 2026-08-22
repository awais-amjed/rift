import 'package:flutter/widgets.dart';
import 'package:rift/data/enums/layout_mode.dart';
import 'package:rift/presentation/responsive/shell_scope.dart';

/// Puts a widget under a [ShellScope], for tests of things that live inside
/// the home shell.
///
/// The panes and their headers reach for the scope to toggle each other,
/// because whether "open" means a saved preference or a drawer depends on how
/// much window there is and no single widget can know that. `ShellScope.of`
/// asserts rather than falling back for that reason — a missing scope is a
/// control wired to nothing, which is exactly the failure a silent default
/// would hide — so a test pumping one of those widgets has to supply it.
///
/// Defaults to [LayoutMode.expanded] with both panes showing: the layout the
/// app is normally in, and the one where nothing is overlaid, so a test that
/// does not care about responsiveness gets the plain case.
Widget withShellScope(
  Widget child, {
  LayoutMode mode = LayoutMode.expanded,
  bool sidebarOpen = true,
  bool membersOpen = true,
  VoidCallback? onToggleSidebar,
  VoidCallback? onToggleMembers,
  VoidCallback? onDismissOverlays,
}) {
  return ShellScope(
    mode: mode,
    sidebarOpen: sidebarOpen,
    membersOpen: membersOpen,
    toggleSidebar: onToggleSidebar ?? () {},
    toggleMembers: onToggleMembers ?? () {},
    dismissOverlays: onDismissOverlays ?? () {},
    child: child,
  );
}
