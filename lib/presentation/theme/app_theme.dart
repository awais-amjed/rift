import 'package:flutter/material.dart';

import 'custom_colors.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CustomColors.primary,
      brightness: Brightness.dark,
      primary: CustomColors.primary,
      onPrimary: Colors.white,
      surface: CustomColors.bgSecondaryDark,
      onSurface: CustomColors.textPrimaryDark,
      surfaceContainerHighest: CustomColors.bgTertiaryDark,
      error: CustomColors.error,
    ),
    scaffoldBackgroundColor: CustomColors.bgSecondaryDark,
    cardColor: CustomColors.bgSecondaryDark,
    dividerColor: CustomColors.borderPrimaryDark,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CustomColors.bgTertiaryDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.borderPrimaryDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.borderPrimaryDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: CustomColors.textTertiaryDark, fontSize: 12),
      hintStyle: TextStyle(color: CustomColors.textQuaternaryDark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: CustomColors.textSecondaryDark),
      bodySmall: TextStyle(color: CustomColors.textTertiaryDark),
      titleMedium: TextStyle(
        color: CustomColors.textPrimaryDark,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(color: CustomColors.textQuaternaryDark),
    ),
  );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CustomColors.primary,
      brightness: Brightness.light,
      primary: CustomColors.primary,
      onPrimary: Colors.white,
      surface: CustomColors.bgSecondaryLight,
      onSurface: CustomColors.textPrimaryLight,
      surfaceContainerHighest: CustomColors.bgTertiaryLight,
      error: CustomColors.error,
    ),
    scaffoldBackgroundColor: CustomColors.bgPrimaryLight,
    cardColor: CustomColors.bgSecondaryLight,
    dividerColor: CustomColors.borderPrimaryLight,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CustomColors.bgTertiaryLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.borderPrimaryLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.borderPrimaryLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: CustomColors.primary, width: 1.5),
      ),
      labelStyle: TextStyle(
        color: CustomColors.textTertiaryLight,
        fontSize: 12,
      ),
      hintStyle: TextStyle(color: CustomColors.textQuaternaryLight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: CustomColors.textSecondaryLight),
      bodySmall: TextStyle(color: CustomColors.textTertiaryLight),
      titleMedium: TextStyle(
        color: CustomColors.textPrimaryLight,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(color: CustomColors.textQuaternaryLight),
    ),
  );
}
