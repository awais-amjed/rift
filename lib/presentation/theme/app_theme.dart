import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'custom_colors.dart';

class AppTheme {
  /// Builds the Material [ThemeData] for one brightness of a palette.
  /// Widgets read colors from `ThemeState` getters; this only feeds the
  /// framework-level defaults (inputs, scaffold, dividers, text).
  static ThemeData fromPalette(AppPalette palette, Brightness brightness) {
    final colors = brightness == Brightness.dark ? palette.dark : palette.light;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        surface: colors.bgSecondary,
        onSurface: colors.textPrimary,
        surfaceContainerHighest: colors.bgTertiary,
        error: CustomColors.error,
      ),
      // The scaffold is the canvas the floating panels sit on, in both modes —
      // panels paint their own background over it.
      scaffoldBackgroundColor: colors.bgPrimary,
      cardColor: colors.bgSecondary,
      dividerColor: colors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.bgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
        hintStyle: TextStyle(color: colors.textQuaternary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: colors.textSecondary),
        bodySmall: TextStyle(color: colors.textTertiary),
        titleMedium: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: TextStyle(color: colors.textQuaternary),
      ),
    );
  }

  static ThemeData dark(AppPalette palette) =>
      fromPalette(palette, Brightness.dark);

  static ThemeData light(AppPalette palette) =>
      fromPalette(palette, Brightness.light);
}
