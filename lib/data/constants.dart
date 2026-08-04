class K {
  // ── Radii ─────────────────────────────────────────────────
  /// The floating panels (sidebar, content, members).
  static const double radiusPanel = 16;
  static const double radiusDialog = 20;

  /// Cards, context menus, popovers.
  static const double radiusCard = 12;

  /// Attachment cards inside a message. A step above a plain card, so they
  /// read as objects dropped into the message rather than part of its text.
  static const double radiusAttachment = 13;

  /// List rows, icon buttons, small controls.
  static const double radiusRow = 10;

  /// Buttons, segmented options and expiry chips. One step above a row, so a
  /// button reads as pressable next to the rows it sits among.
  static const double radiusButton = 11;

  /// Squircle avatars and server chips are radius ≈ size/3; the rail's 40px
  /// chips land on 13.
  static const double radiusRailChip = 13;

  /// Fully round — chips, pills, badges, presence dots.
  static const double radiusPill = 999;

  /// Avatars are squircles rather than circles: radius is this fraction of
  /// the avatar's size.
  static const double avatarRadiusRatio = 1 / 3;

  // ── Controls ──────────────────────────────────────────────
  /// A standalone button.
  static const double controlHeight = 38;

  /// Text fields, dropdowns, segmented options and dialog-footer buttons —
  /// one step taller than a standalone button, so a form's controls line up
  /// with each other rather than with the buttons scattered around the app.
  static const double fieldHeight = 40;

  /// Square icon buttons.
  static const double iconButtonSize = 36;

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

  /// Settings' nav panel. Narrower than the home sidebar — it holds three
  /// labels, not a channel tree.
  static const double settingsNavWidth = 264;

  // ── Message rows ──────────────────────────────────────────
  /// Left/right padding on a message row. The design's rows run wider than
  /// the panel's own padding so the text has room to breathe at the edges.
  static const double messageRowHPad = 20;

  /// The avatar gutter. Continuation rows leave it empty, which is what makes
  /// a group read as one block of speech rather than repeated headers.
  static const double messageGutter = 34;

  // ── Chat composer ─────────────────────────────────────────
  /// Every control in the composer row (attach, emoji, mic, send) is a square
  /// of this size, and the text field is floored to it, so the icons and the
  /// text share one centre line whatever the font's metrics are.
  static const double composerControlSize = 34;
  static const double composerControlRadius = 10;
  static const double composerIconSize = 19;
  static const double composerFontSize = 13.5;
  static const double composerLineHeight = 1.4;

  /// Room above/below the composer text, applied as a plain symmetric padding
  /// rather than the decorator's `contentPadding` so it can't bias the text.
  static const double composerFieldVPad = 4;
}
