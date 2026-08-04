class K {
  // ── Radii ─────────────────────────────────────────────────
  /// The floating panels (sidebar, content, members).
  static const double radiusPanel = 16;
  static const double radiusDialog = 20;

  /// Cards, context menus, popovers.
  static const double radiusCard = 12;

  /// List rows, icon buttons, small controls.
  static const double radiusRow = 10;

  /// Squircle avatars and server chips are radius ≈ size/3; the rail's 40px
  /// chips land on 13.
  static const double radiusRailChip = 13;

  /// Fully round — chips, pills, badges, presence dots.
  static const double radiusPill = 999;

  /// Avatars are squircles rather than circles: radius is this fraction of
  /// the avatar's size.
  static const double avatarRadiusRatio = 1 / 3;

  // ── Panel workspace ───────────────────────────────────────
  /// Gap between the floating panels, and between them and the window edge.
  static const double panelGutter = 10;

  // ── Title bar ─────────────────────────────────────────────
  static const double titleBarHeight = 38;
  static const double titleBarHotZoneHeight = 40;
  static const double titleBarHiddenSidebarPadding = 20;

  // ── Server rail ───────────────────────────────────────────
  /// The rail lives inside the sidebar panel, so its width is part of
  /// [sidebarWidth] rather than added to it.
  static const double serverRailWidth = 58;
  static const double serverRailChipSize = 40;

  // ── Sidebar ───────────────────────────────────────────────
  /// Rail + channel column, as one floating panel.
  static const double sidebarWidth = 346;

  /// Right-hand member list. Narrower than the left sidebar — it holds one
  /// short name per row, not channel trees.
  static const double membersSidebarWidth = 232;

  /// Collapsed member list: just wide enough for the reopen button.
  static const double membersSidebarCollapsedWidth = 42;

  // ── Chat composer ─────────────────────────────────────────
  /// Every control in the composer row (attach, emoji, mic, send) is a square
  /// of this size, and the text field is floored to it, so the icons and the
  /// text share one centre line whatever the font's metrics are.
  static const double composerControlSize = 38;
  static const double composerIconSize = 20;
  static const double composerFontSize = 14;
  static const double composerLineHeight = 1.4;

  /// Room above/below the composer text, applied as a plain symmetric padding
  /// rather than the decorator's `contentPadding` so it can't bias the text.
  static const double composerFieldVPad = 4;
}
