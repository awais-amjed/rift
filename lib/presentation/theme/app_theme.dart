import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_text.dart';
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
      fontFamily: AppText.sans,
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
        labelStyle: AppText.secondary.copyWith(color: colors.textTertiary),
        hintStyle: AppText.body.copyWith(color: colors.textQuaternary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      // Framework-level defaults only — widgets style their own text from
      // AppText. These keep stray Material text (menus, tooltips) on scale.
      textTheme: TextTheme(
        titleLarge: AppText.sectionTitle.copyWith(color: colors.textPrimary),
        titleMedium: AppText.panelTitle.copyWith(color: colors.textPrimary),
        bodyMedium: AppText.body.copyWith(color: colors.textSecondary),
        bodySmall: AppText.secondary.copyWith(color: colors.textTertiary),
        labelSmall: AppText.label.copyWith(color: colors.textQuaternary),
      ),
    );
  }

  static ThemeData dark(AppPalette palette) =>
      fromPalette(palette, Brightness.dark);

  static ThemeData light(AppPalette palette) =>
      fromPalette(palette, Brightness.light);
}
