/// Layout numbers shared across files, grouped by the part of the app they
/// shape. A number one file uses stays a named constant in that file instead.
class K {
  // ── Radii ─────────────────────────────────────────────────
  // Three steps. A surface picks the one for what it is, never a value of
  // its own: a fifth radius is how the scale grew to eight.
  /// List rows, buttons, fields, chips, icon buttons — anything you press.
  static const double radiusRow = 8;

  /// Cards, context menus, popovers, attachments, icon badges — and the
  /// floating panels, dialogs and the voice control bar.
  static const double radiusCard = 12;

  /// Fully round — pills, presence dots, colour swatches.
  static const double radiusPill = 999;

  /// Not a step of the scale: the rail's server chips are squircles, and a
  /// squircle's radius follows its size (see [avatarRadiusRatio]).
  static const double radiusRailChip = serverRailChipSize * avatarRadiusRatio;

  /// Avatars are squircles rather than circles: radius is this fraction of
  /// the avatar's size.
  static const double avatarRadiusRatio = 0.28;

  /// The bar across the top of a pane: the chat header and the voice
  /// stage's context strip. One height, so switching panes does not jump
  /// the content under it by the difference.
  static const double paneHeaderHeight = 52;

  // ── Controls ──────────────────────────────────────────────
  /// A button. The same as [touchTargetMin], so the app has one control
  /// height rather than a mouse one and a finger one.
  static const double controlHeight = touchTargetMin;

  /// Text fields, dropdowns and segmented options.
  static const double fieldHeight = controlHeight;

  /// Square icon buttons.
  static const double iconButtonSize = 40;

  // ── Dialog widths ─────────────────────────────────────────
  /// A form dialog whose fields run in one column.
  static const double dialogWidth = 480;

  /// A person's profile. Wide enough for who they are and what you can do
  /// about them to sit side by side and still clear `ModalColumns`' own
  /// arithmetic: two 260 columns, the rule and its gutters, and the modal's
  /// padding. That is what keeps a profile one screen instead of a scroll.
  static const double profileWidth = 640;

  /// A form dialog holding two groups side by side — see `ModalColumns`,
  /// which needs roughly this much before it stops stacking them.
  static const double dialogWidthWide = 760;

  /// Three groups side by side. `ModalColumns` wants 300 a column plus the two
  /// rules between them, so anything under about 1000 stacks instead — which
  /// still happens, correctly, on a narrow window.
  static const double dialogWidthWidest = 1040;

  /// The manage-server dialog, which is wider than [dialogWidthWidest]
  /// because it spends 196 of its width on the nav column before its pages
  /// see any: `ModalColumns` needs 998 for three columns, the nav, its rule
  /// and the page padding take 245, so under about 1243 the widest page
  /// stacks into one long scroll. This is the width at which Overview stops
  /// doing that.
  static const double manageDialogWidth = 1280;

  /// The manage-server dialog's height, as tall as the window allows up to
  /// this. Fixed for a given window rather than sized to the page, because
  /// its pages swap inside one frame and a frame that resized with each page
  /// would make the nav jump.
  static const double manageDialogHeight = 900;

  /// How much of the window's height the manage dialog may take when
  /// [manageDialogHeight] does not fit — a laptop gets a shorter dialog
  /// rather than one running off the screen.
  static const double manageDialogHeightFraction = 0.88;

  /// The column an onboarding step's form keeps to, so every step's fields
  /// line up with the one before it however wide the window is.
  static const double onboardingFormWidth = 360;

  // ── Touch ─────────────────────────────────────────────────
  /// The shortest a row may be where a finger is the pointer.
  ///
  /// Both Material and HIG put the floor around here, and the app's rows sit
  /// well under it: a [NavRow] is about 32px, which is a comfortable mouse
  /// target and a fiddly thumb one. Applied by padding rather than by a fixed
  /// height, so a row that is naturally taller — one with a subtitle — is
  /// left alone rather than squashed to this.
  static const double touchTargetMin = 44;

  /// A call to action at the foot of a phone screen — a dialog's footer, an
  /// onboarding step's Continue. A thumb at the bottom of a phone is not a
  /// cursor. Only there: every other control, on a phone too, is
  /// [controlHeight]. Applied by `AppButtonHeight`, never by passing it to
  /// each button.
  static const double thumbCtaHeight = 56;

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

  // ── Sidebar peek ──────────────────────────────────────────
  // Resting the pointer on the middle of the left edge slides a hidden
  // sidebar out over the content, for a look at a channel without undoing
  // the layout. The last version of this opened on any touch of the edge and
  // shut the moment the pointer left; these are what keep it from doing
  // either.

  /// How far down the left edge the peek's hot zone starts and ends, as a
  /// fraction of the window's height. The middle only: the corners are where
  /// the pointer goes on its way to the rail, the title bar and the edge tab.
  static const double sidebarPeekZoneStart = 0.3;
  static const double sidebarPeekZoneEnd = 0.7;

  /// How long the pointer has to rest in the hot zone. Long enough that a
  /// pointer crossing the edge on its way somewhere else does not open it.
  static const Duration sidebarPeekDwell = Duration(milliseconds: 150);

  /// How long the pointer can be off the panel before it slides away — so
  /// overshooting its edge, or cutting a corner back to it, does not cost
  /// the peek.
  static const Duration sidebarPeekLinger = Duration(milliseconds: 400);

  /// How long a pointer has to rest before a tooltip appears.
  ///
  /// Written out at fourteen call sites, which is fourteen chances for one
  /// button in a row of identical buttons to feel different from its
  /// neighbours. Long enough that tooltips do not flicker up while somebody is
  /// crossing a toolbar on the way somewhere else, short enough to answer a
  /// deliberate hover.
  static const Duration tooltipDelay = Duration(milliseconds: 400);

  /// How long a copy button says "Copied" before it offers to copy again.
  /// A one-time secret's button keeps saying it instead: it is copied once.
  static const Duration copiedHold = Duration(seconds: 2);

  /// How long a search field waits after the last keystroke before asking the
  /// server.
  ///
  /// Every search field in the app is meant to feel like the same control, and
  /// two of the three that set this said so in a comment while holding their
  /// own copy of the number. Long enough to skip the letters somebody types on
  /// the way to a word, short enough that the results feel like a response.
  static const Duration searchDebounce = Duration(milliseconds: 250);

  /// Right-hand member list. Narrower than the left sidebar — it holds one
  /// short name per row, not channel trees. Hidden it takes no width at all;
  /// it used to leave a 42px strip behind for its reopen button, which is a lot
  /// of window to keep for one icon. An [EdgeTab] brings it back instead.
  static const double membersSidebarWidth = 232;

  /// How far the member list may be dragged. The floor keeps a name and its
  /// role pill on one line; the ceiling, and the window share, keep it from
  /// eating the chat it sits beside — it is the least-consulted of the three
  /// panes, so it gets the smallest share.
  static const double membersSidebarMinWidth = 200;
  static const double membersSidebarMaxWidth = 420;
  static const double membersSidebarMaxWindowFraction = 0.35;

  // ── Call controls ───────────────────────────────────────
  /// How far above the stage's bottom edge the floating call controls sit.
  static const double callBarOffset = 28;

  /// Where the floating call controls' top edge is, measured up from the
  /// stage's bottom: the offset plus 46px buttons in 8px of padding. What the
  /// stage keeps clear, so the controls do not sit on somebody's tile.
  static const double callBarClearance = callBarOffset + 64;

  /// The same for the pill a phone leaves behind when its controls fade:
  /// the call's length and the mic, in a 40px capsule.
  static const double callPillClearance = callBarOffset + 40;

  /// Settings' nav panel. Narrower than the home sidebar — it holds three
  /// labels, not a channel tree.
  static const double settingsNavWidth = 264;

  /// How wide a page of settings is allowed to get, however wide the window
  /// is.
  ///
  /// A settings row puts its label at one edge and its control at the other,
  /// so an unbounded row on a 1500px window leaves a switch some 900px from
  /// the words it belongs to, and the line explaining it runs to about 130
  /// characters — roughly twice a comfortable measure. One pane already
  /// capped itself and three did not, which is how the same screen came to
  /// disagree with itself about how wide a setting is.
  ///
  /// Applied once by the settings screen, so a pane cannot opt out of it.
  /// A *control* inside a pane may still be narrower than this — a theme
  /// picker or a segmented choice is sized to its own content.
  static const double settingsMeasure = 720;

  // ── Message rows ──────────────────────────────────────────
  /// Left/right padding on a message row. The design's rows run wider than
  /// the panel's own padding so the text has room to breathe at the edges.
  static const double messageRowHPad = 20;

  /// The avatar gutter. Continuation rows leave it empty, which is what makes
  /// a group read as one block of speech rather than repeated headers.
  static const double messageGutter = 34;

  /// The rule down the left of a message a jump has just landed on. Wider
  /// than a hairline on purpose: the tint behind it fades, and this is what
  /// is still legible in the last third of that.
  static const double messageFlashRule = 2;

  // ── Chat composer ─────────────────────────────────────────
  /// Every control in the composer row (attach, emoji, mic, send) is a square
  /// of this size, and the text field is floored to it, so the icons and the
  /// text share one centre line whatever the font's metrics are.
  static const double composerControlSize = 36;
  static const double composerIconSize = 19;
  static const double composerLineHeight = 1.4;

  /// Room above/below the composer text, applied as a plain symmetric padding
  /// rather than the decorator's `contentPadding` so it can't bias the text.
  static const double composerFieldVPad = 4;
}
