import '../constants.dart';

/// How much room the window has, and therefore which of the three panes can be
/// docked at once.
///
/// The app is one workspace at every size, not a desktop layout and a separate
/// mobile one: the same sidebar and the same member list are shown either
/// **docked**, taking their width out of the row, or **overlaid**, floating
/// above the content with a scrim behind them. Only where they are mounted
/// changes, which is why a phone and a half-width desktop window get the same
/// treatment without either being a special case.
enum LayoutMode {
  /// Neither side pane fits. Content runs edge to edge and both overlay.
  compact,

  /// The sidebar fits; the member list does not.
  medium,

  /// Everything docks — the layout this app was built in.
  expanded;

  /// The mode for a window [width] logical pixels across.
  ///
  /// Width alone, deliberately. Height does not change what can be docked
  /// side by side, and asking about the platform instead would give a tablet
  /// the phone layout and a half-screen desktop window the wrong one entirely.
  static LayoutMode forWidth(double width) {
    if (width >= K.breakpointExpanded) return LayoutMode.expanded;
    if (width >= K.breakpointMedium) return LayoutMode.medium;
    return LayoutMode.compact;
  }

  /// Whether the left sidebar floats above the content instead of docking.
  bool get sidebarIsOverlay => this == LayoutMode.compact;

  /// Whether the member list floats above the content instead of docking.
  bool get membersIsOverlay => this != LayoutMode.expanded;

  /// One pane at a time, so navigation controls belong in the content's own
  /// header rather than on the window edges.
  bool get isCompact => this == LayoutMode.compact;
}
