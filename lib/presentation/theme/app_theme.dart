import 'package:flutter/material.dart';

import '../../logic/services/host_platform.dart';
import 'app_palette.dart';
import 'app_shadows.dart';
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
      // A tooltip explains a control you are pointing at, and on a touchscreen
      // there is no pointing — so it fires on a long press instead, which is
      // the gesture the context menus want. Tooltip's recognizer sits *inside*
      // ContextMenuRegion's and wins the arena, so long-pressing a server chip
      // showed the server's name where its menu should have been, and every
      // tooltipped control inside a menu region was quietly the same.
      //
      // Manual means it never fires by itself. Nothing is lost: the label it
      // would have shown is on a control the user is already touching.
      //
      // The look is set here rather than left to Material, which paints a
      // light pill with dark text — correct for a light app and glaringly
      // wrong in this one, which is why every tooltip in Rift looked like it
      // belonged to a different program. These match [PopoverSurface], because
      // a tooltip is the smallest thing in that family.
      //
      // `waitDuration` is short on purpose: a small target with a long delay
      // is indistinguishable from one that has no tooltip at all.
      tooltipTheme: TooltipThemeData(
        triggerMode: HostPlatform.isMobile ? TooltipTriggerMode.manual : null,
        waitDuration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.borderElevated),
          boxShadow: AppShadows.popover,
        ),
        textStyle: AppText.meta.copyWith(color: colors.textSecondary),
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
