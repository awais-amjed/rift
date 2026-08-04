import 'package:flutter/material.dart';

import 'palettes/abyss_palette.dart';
import 'palettes/ember_palette.dart';
import 'palettes/indigo_palette.dart';
import 'palettes/mono_palette.dart';

/// One brightness mode's worth of palette colors.
///
/// Widgets never read these directly — they go through the semantic getters
/// on `ThemeState`, which pick the right mode.
///
/// The surfaces form a deliberate ladder, darkest first: [bgPrimary] is the
/// canvas the floating panels sit *on* and is never the background of content;
/// [bgContent] and [bgSecondary] are the panels themselves; [bgTertiary] is
/// inset (fields, composer); [bgElevated] floats above everything (menus,
/// popovers, toasts).
class PaletteColors {
  // ── Accent ────────────────────────────────────────────────────────────────
  final Color primary;
  final Color onPrimary;

  /// Lighter accent for text and icons on dark surfaces, where [primary] at
  /// small sizes is too dim to read.
  final Color accentBright;

  /// End stop of the action gradient (primary buttons, send). Starts at
  /// [primary].
  final Color accentGradientEnd;

  /// Second stop for identity gradients (server icons, avatars).
  final Color gradientPartner;

  // ── Surfaces, darkest to lightest ─────────────────────────────────────────
  /// The canvas behind the floating panels. Not a content background.
  final Color bgPrimary;

  /// Content panels — chat, voice stage, settings body.
  final Color bgContent;

  /// Chrome panels — sidebar, members, nav.
  final Color bgSecondary;

  /// Inset surfaces — text fields, the composer bar.
  final Color bgTertiary;

  /// Elevated overlay surfaces (popovers, context menus, floating bars).
  final Color bgElevated;

  /// The server rail's faint wash over the sidebar panel.
  final Color railStrip;

  final Color bgHover;
  final Color bgActive;

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textQuaternary;

  // ── Chrome ────────────────────────────────────────────────────────────────
  final Color border;

  /// Border for elevated surfaces, which need more contrast than [border]
  /// because they sit over lit content rather than the canvas.
  final Color borderElevated;

  final Color sidebarBg;

  // ── Accent-derived active states (selected channel, selected cards) ────────
  final Color channelActiveBg;
  final Color channelActiveText;
  final Color channelActiveBorder;

  const PaletteColors({
    required this.primary,
    required this.onPrimary,
    required this.accentBright,
    required this.accentGradientEnd,
    required this.gradientPartner,
    required this.bgPrimary,
    required this.bgContent,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgElevated,
    required this.railStrip,
    required this.bgHover,
    required this.bgActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.border,
    required this.borderElevated,
    required this.sidebarBg,
    required this.channelActiveBg,
    required this.channelActiveText,
    required this.channelActiveBorder,
  });

  // ── Derived gradients ─────────────────────────────────────────────────────

  /// Primary buttons and the composer's send control.
  LinearGradient get actionGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accentGradientEnd],
  );

  /// Server icons and avatars belonging to the local user.
  LinearGradient get identityGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, gradientPartner],
  );

  /// Fill behind a selected channel/DM row — fades out to the right so the
  /// row reads as lit from its leading edge rather than as a solid block.
  LinearGradient get activeRowGradient => LinearGradient(
    colors: [primary.withValues(alpha: 0.14), primary.withValues(alpha: 0.05)],
  );
}

/// A user-selectable color palette: accent + neutrals for both modes.
///
/// Semantic status colors (success/warning/error, speaking-green,
/// muted-rose) are shared across palettes and live in `CustomColors` —
/// they must never be repurposed as accents (AGENTS.md).
class AppPalette {
  final String id;
  final String name;
  final String description;
  final PaletteColors dark;
  final PaletteColors light;

  const AppPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.dark,
    required this.light,
  });

  static const List<AppPalette> all = [
    indigoPalette,
    abyssPalette,
    emberPalette,
    monoPalette,
  ];

  static AppPalette byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => indigoPalette);
}
