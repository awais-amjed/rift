import 'package:flutter/material.dart';

/// Semantic status colors — shared across every [AppPalette] and identical in
/// both brightness modes. These must never be repurposed as accents; all
/// themed colors (accent + neutrals) live in `app_palette.dart` and are read
/// via `ThemeState` getters.
class CustomColors {
  static const Color success = Color(0xFF22C55E); // Emerald-500
  static const Color warning = Color(0xFFFBBF24); // Amber-400
  static const Color error = Color(0xFFF43F5E); // Rose-500
  static const Color errorDark = Color(0xFFE11D48); // Rose-600

  /// Text and icons on an [error] fill — a danger button, Leave, hang up.
  static const Color onError = Color(0xFFFFFFFF);

  /// Icons on a [success] fill — answering a call. Dark rather than white:
  /// white on Emerald-500 is under 2.5:1, and the glyph is the whole label.
  static const Color onSuccess = Color(0xFF052E16); // Green-950

  /// Online/speaking presence indicator.
  static const Color userStatusOnline = Color(0xFF22C55E);

  // ── Ink on a light surface ─────────────────────────────────
  /// The three statuses a step darker, for *text and small icons* on a light
  /// theme. The colours above were picked against dark surfaces: on a light
  /// one, amber on its own wash came to 1.55:1 and green to 2.1:1 — and the
  /// amber one is the "Not encrypted" badge, which has to be read. Fills, dots
  /// and bars keep the shared colours. Widgets never pick these directly; they
  /// ask `ThemeState.statusInk`.
  static const Color successInkLight = Color(0xFF166534); // Green-800
  static const Color warningInkLight = Color(0xFFB45309); // Amber-700
  static const Color errorInkLight = Color(0xFFBE123C); // Rose-700

  /// And the one that falls short the other way: rose-500 is a fill, and as
  /// 13px text on a dark menu with its own wash behind it came to about 4:1.
  static const Color errorInkDark = Color(0xFFFB7185); // Rose-400
}
