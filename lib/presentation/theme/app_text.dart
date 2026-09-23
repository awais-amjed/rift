import 'package:flutter/material.dart';

/// The app's type scale: seven sizes, 11 / 12 / 13 / 14 / 15 / 18 / 21.
///
/// Every style here is one of those seven. A call site never sets a size of
/// its own — `copyWith(fontSize:)` is how a scale grows thirteen steps that
/// are half a pixel apart — so if a place needs a size, it needs a token,
/// and the token has to land on one of the seven.
///
/// 18 was the sixth's replacement rather than an addition to it: a modal
/// that becomes a full screen on a phone used to take the 21 meant for a
/// hero, and the only step under it was the 15 a section heading uses. See
/// [modalPageTitle]. Adding an eighth needs the same kind of argument —
/// two things that must not look alike and no room between them.
///
/// Styles carry size, weight, spacing and family — never colour. Colour is
/// themed and comes from `ThemeState`, so call sites finish a style with
/// `.copyWith(color: theme.textSecondary)`. Keeping the two apart is what
/// stops a hard-coded colour from sneaking in behind a text style.
///
/// Mono is reserved for the things proportional type handles badly: figures
/// that must line up or tick in place, keyboard chips, and strings meant to
/// be copied exactly (invite links, recovery keys).
class AppText {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';

  // ── 21 ────────────────────────────────────────────────────────────────────

  /// The hero at the top of an arrival: onboarding steps, the banned notice,
  /// welcome. Not a page you are passing through — that is [modalPageTitle].
  static const TextStyle pageTitle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.2,
  );

  // ── 18 ────────────────────────────────────────────────────────────────────

  /// The title of a page you are passing *through*: a modal that becomes a
  /// full screen on a phone.
  ///
  /// The seventh size, and the reason for it. Such a page used to borrow
  /// [pageTitle], which is the hero size — so "Manage server" was set in the
  /// same type as the welcome screen, on a screen narrow enough for that to
  /// be most of the width. The step below it is 15, which is what a section
  /// heading *inside* a page uses, so dropping to that would have made the
  /// name of the screen indistinguishable from a group within it. 18 keeps
  /// the three apart: hero, page, section.
  static const TextStyle modalPageTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.15,
  );

  // ── 15 ────────────────────────────────────────────────────────────────────

  /// A dialog's title, in its header.
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// Headings inside a page — a settings group, an empty state's title.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// The title of a panel or its header bar (server name, channel name).
  static const TextStyle panelTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// A recovery key, set to be read aloud and typed elsewhere.
  static const TextStyle mnemonic = TextStyle(
    fontFamily: mono,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.4,
  );

  // ── 14 ────────────────────────────────────────────────────────────────────

  /// Message text, dialog prose, notices. The generous line height is what
  /// makes a wall of chat readable, so it belongs in the token rather than
  /// at each call site.
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// What the user types: text fields and the composer.
  static const TextStyle input = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  // ── 13 ────────────────────────────────────────────────────────────────────

  /// A list row that is active, unread, or otherwise wants weight. Also the
  /// label of a secondary button and a selected segment.
  static const TextStyle row = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// A list row at rest, an unselected segment.
  static const TextStyle rowQuiet = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// The heaviest thing at row size: a message author, a primary button's
  /// label, a palette card's name.
  static const TextStyle strong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// A string meant to be copied exactly — an invite link, a server address.
  static const TextStyle code = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ── 12 ────────────────────────────────────────────────────────────────────

  /// Helper lines, previews, descriptions under a row.
  static const TextStyle secondary = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// A selected option chip, a status pill with a word in it ("Encrypted").
  static const TextStyle secondaryStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // ── 11 ────────────────────────────────────────────────────────────────────

  /// Sub-labels under a title — the E2E note, presence lines.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  /// The uppercase dividers between groups: TEXT, VOICE, ONLINE — 3.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  /// Small emphasis at label size: a date divider, a reaction count.
  static const TextStyle chip = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Unread counts and other numeric badges.
  static const TextStyle badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  /// Role pills on member rows: Admin, Mod, Bot, Banned.
  static const TextStyle roleChip = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  /// Message timestamps and other quiet metadata. Sans, not mono — tabular
  /// figures keep the column straight without a second family on every row.
  static const TextStyle meta = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Figures that update in place — session timers, ping, counts. Mono and
  /// tabular so the text doesn't shift width as the digits change.
  static const TextStyle figure = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Keyboard chips (⌘K, Left Alt).
  static const TextStyle kbd = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );
}
