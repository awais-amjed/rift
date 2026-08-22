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

  /// The floating voice control bar. Softer than a panel but stopping well
  /// short of a stadium, so the row of square buttons inside still reads as a
  /// row rather than as something poured into a capsule.
  static const double radiusVoicePill = 18;

  /// Avatars are squircles rather than circles: radius is this fraction of
  /// the avatar's size.
  static const double avatarRadiusRatio = 1 / 3;

  // ── Controls ──────────────────────────────────────────────
  /// A standalone button.
  static const double controlHeight = 38;

  /// Text fields, dropdowns and segmented options — one step taller than a
  /// standalone button, so a form's controls line up with each other rather
  /// than with the buttons scattered around the app. A dialog's footer
  /// buttons are *not* form controls: they sit below the divider and take
  /// [controlHeight].
  static const double fieldHeight = 40;

  /// Square icon buttons.
  static const double iconButtonSize = 36;

  // ── Dialog widths ─────────────────────────────────────────
  /// A form dialog whose fields run in one column.
  static const double dialogWidth = 480;

  /// A form dialog holding two groups side by side — see `ModalColumns`,
  /// which needs roughly this much before it stops stacking them.
  static const double dialogWidthWide = 760;

  /// Three groups side by side. `ModalColumns` wants 300 a column plus the two
  /// rules between them, so anything under about 1000 stacks instead — which
  /// still happens, correctly, on a narrow window.
  static const double dialogWidthWidest = 1040;

  // ── Touch ─────────────────────────────────────────────────
  /// The shortest a row may be where a finger is the pointer.
  ///
  /// Both Material and HIG put the floor around here, and the app's rows sit
  /// well under it: a [NavRow] is about 32px, which is a comfortable mouse
  /// target and a fiddly thumb one. Applied by padding rather than by a fixed
  /// height, so a row that is naturally taller — one with a subtitle — is
  /// left alone rather than squashed to this.
  static const double touchTargetMin = 44;

  /// The slot the floating pane-menu button occupies at the top-left of a
  /// content pane that has no header of its own — the voice area.
  ///
  /// It floats over the content rather than sitting in a row, so anything that
  /// *does* draw across the top has to leave this much clear or it lands
  /// underneath: the button's 10px offset, its 32px box, and a gap after it.
  static const double paneMenuButtonSlot = 48;

  // ── Layout breakpoints ────────────────────────────────────
  /// Where the member list stops being worth 232px of a shrinking window.
  ///
  /// Below this the sidebar and the content between them already have less
  /// than [sidebarMinWidth] + a readable measure, so the member list — the
  /// least-consulted of the three panes — is the first to become an overlay.
  static const double breakpointExpanded = 1100;

  /// Where a docked sidebar stops fitting at all.
  ///
  /// [sidebarMinWidth] plus a chat column narrow enough to still hold a
  /// message row lands just under 700, so below this the sidebar overlays too
  /// and the content runs edge to edge.
  static const double breakpointMedium = 700;

  /// How wide a DM conversation header must be before each status chip earns
  /// its place.
  ///
  /// Keyed off the header's *own* width rather than the window's `LayoutMode`.
  /// A medium window docks the sidebar **and** the DM list, so the conversation
  /// beside them is narrower than the whole content column is on a phone —
  /// sizing the chips by window mode is exactly what let the header overflow.
  static const double dmHeaderTierChipMin = 300;
  static const double dmHeaderEncryptedChipMin = 460;

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
  /// Rail + channel column, as one floating panel. Draggable — this is where
  /// it starts, and what it returns to on a double-click.
  static const double sidebarWidth = 346;

  /// How narrow the sidebar may be dragged. The rail takes
  /// [serverRailWidth] of it whatever happens, so this floor is really about
  /// what is left for the channel column: at 260 that is ~200px, still enough
  /// for a channel name and its unread badge.
  static const double sidebarMinWidth = 260;

  /// How wide it may be dragged. Also capped against the window at
  /// [sidebarMaxWindowFraction], so it can never crowd out the content.
  static const double sidebarMaxWidth = 560;
  static const double sidebarMaxWindowFraction = 0.5;

  /// How much content an overlaid sidebar leaves showing beside it.
  ///
  /// Wide enough to be a comfortable tap target for dismissing the drawer, and
  /// — the part that decides the number — wide enough to read as content
  /// behind a panel rather than as a docked column. On a dark theme the scrim
  /// is dark on dark and does almost none of that work, so the gap has to.
  static const double sidebarOverlayPeek = 72;

  /// The grab strip between the sidebar and the content. It occupies the
  /// gutter that used to be an empty [panelGutter] gap, so making the sidebar
  /// resizable cost no layout width.
  static const double sidebarResizeHandleWidth = panelGutter;

  /// How long the sidebar takes to open or close. Shared by all three moving
  /// parts — the pinned panel's width, the unpinned panel's slide, and the edge
  /// tab — so they arrive together instead of at three different times. The
  /// curve that goes with it is `AppMotion.panel`; curves are Flutter's, and
  /// this file is meant to stay free of it.
  static const Duration sidebarMotion = Duration(milliseconds: 220);

  /// Right-hand member list. Narrower than the left sidebar — it holds one
  /// short name per row, not channel trees. Hidden it takes no width at all;
  /// it used to leave a 42px strip behind for its reopen button, which is a lot
  /// of window to keep for one icon. An [EdgeTab] brings it back instead.
  static const double membersSidebarWidth = 232;

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
