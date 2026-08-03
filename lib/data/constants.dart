class K {
  // ── Title bar ─────────────────────────────────────────────
  static const double titleBarHeight = 40;
  static const double titleBarHotZoneHeight = 40;
  static const double titleBarHiddenSidebarPadding = 20;

  // ── Sidebar ───────────────────────────────────────────────
  static const double sidebarWidth = 280;

  /// Right-hand member list. Narrower than the left sidebar — it holds one
  /// short name per row, not channel trees.
  static const double membersSidebarWidth = 220;

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
