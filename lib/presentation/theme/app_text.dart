import 'package:flutter/material.dart';

/// The app's type scale.
///
/// Styles here carry size, weight, spacing and family — never colour. Colour
/// is themed and comes from `ThemeState`, so call sites finish a style with
/// `.copyWith(color: theme.textSecondary)`. Keeping the two apart is what
/// stops a hard-coded colour from sneaking in behind a text style.
///
/// Mono is reserved for the two things proportional type handles badly:
/// figures that must line up or tick in place (timestamps, timers, counts),
/// and keyboard chips.
class AppText {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';

  // ── Headings ──────────────────────────────────────────────────────────────

  /// Screen titles (settings pages, onboarding steps).
  static const TextStyle pageTitle = TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
  );

  static const TextStyle dialogTitle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// Headings inside a page — a settings group, a dialog section.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// The title of a panel or its header bar (server name, channel name).
  static const TextStyle panelTitle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
  );

  // ── Rows and body ─────────────────────────────────────────────────────────

  /// A list row that is active, unread, or otherwise wants weight.
  static const TextStyle row = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  /// A list row at rest.
  static const TextStyle rowQuiet = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
  );

  /// Message text and prose. The generous line height is what makes a wall of
  /// chat readable, so it belongs in the token rather than at each call site.
  static const TextStyle body = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const TextStyle secondary = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// Sub-labels under a title — the E2E note, presence lines.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  // ── Micro-labels and chips ────────────────────────────────────────────────

  /// The uppercase dividers between groups: TEXT, VOICE, ONLINE — 3.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// Pill chips carrying a short status word ("Encrypted", "Central").
  static const TextStyle chip = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
  );

  /// Unread counts and other numeric badges.
  static const TextStyle badge = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );

  /// Role tags on member rows: ADMIN, MOD.
  static const TextStyle roleChip = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  // ── Mono ──────────────────────────────────────────────────────────────────

  /// Message timestamps and other quiet metadata.
  static const TextStyle meta = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    fontWeight: FontWeight.w400,
  );

  /// Figures that update in place — session timers, ping, counts. Tabular so
  /// the text doesn't shift width as the digits change.
  static const TextStyle figure = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Keyboard chips (⌘K).
  static const TextStyle kbd = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    fontWeight: FontWeight.w400,
  );
}
