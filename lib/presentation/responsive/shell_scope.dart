import 'package:flutter/widgets.dart';

import '../../data/enums/layout_mode.dart';

/// The current [LayoutMode], whether each side pane is showing, and the one
/// way to toggle them.
///
/// A pane's openness comes from two different places depending on where it is
/// mounted, and nothing below this should have to know which. **Docked**, it
/// is a saved preference in `AppCubit` — the user chose to work without a
/// member list and expects that to survive a restart. **Overlaid**, it is
/// throwaway state that always starts closed, because a drawer that restored
/// itself open would cover the app on launch, and because narrowing the window
/// for a moment must not overwrite a preference chosen for a wide one.
///
/// So the edge tabs, the header buttons and the channel list all call
/// [toggleSidebar] / [toggleMembers] / [dismissOverlays] and let the shell
/// decide which of the two it means.
class ShellScope extends InheritedWidget {
  final LayoutMode mode;

  /// Whether each pane is showing, already resolved for [mode].
  final bool sidebarOpen;
  final bool membersOpen;

  final VoidCallback toggleSidebar;
  final VoidCallback toggleMembers;

  /// Closes whatever is overlaid, and does nothing to a docked pane. Called
  /// on the scrim and after navigating, where the point is to get out of the
  /// way rather than to change a preference.
  final VoidCallback dismissOverlays;

  const ShellScope({
    super.key,
    required this.mode,
    required this.sidebarOpen,
    required this.membersOpen,
    required this.toggleSidebar,
    required this.toggleMembers,
    required this.dismissOverlays,
    required super.child,
  });

  static ShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope above this widget');
    return scope!;
  }

  /// For widgets that are also used outside the home shell — settings and the
  /// onboarding flow build their own layout and have no panes to toggle.
  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) =>
      mode != old.mode ||
      sidebarOpen != old.sidebarOpen ||
      membersOpen != old.membersOpen;
}

/// [LayoutMode] for the current window, for widgets that only need to know how
/// much room they have and have no interest in the panes.
///
/// Reads the media query directly rather than the shell, so it works on every
/// screen — settings and onboarding included — and rebuilds only on a resize.
extension LayoutModeContext on BuildContext {
  LayoutMode get layoutMode =>
      LayoutMode.forWidth(MediaQuery.sizeOf(this).width);
}
