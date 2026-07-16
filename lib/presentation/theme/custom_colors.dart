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

  /// Online/speaking presence indicator.
  static const Color userStatusOnline = Color(0xFF22C55E);
}
