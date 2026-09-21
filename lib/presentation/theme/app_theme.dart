import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../../logic/services/host_platform.dart';
import 'app_palette.dart';
import 'app_shadows.dart';
import 'app_text.dart';
import 'custom_colors.dart';

class AppTheme {
  static const _clickable = ButtonStyle(
    mouseCursor: WidgetStateMouseCursor.clickable,
  );

  /// Builds the Material [ThemeData] for one brightness of a palette.
  /// Widgets read colors from `ThemeState` getters; this only feeds the
  /// framework-level defaults (inputs, scaffold, dividers, text).
  static ThemeData fromPalette(AppPalette palette, Brightness brightness) {
    final colors = brightness == Brightness.dark ? palette.dark : palette.light;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      // What widgets actually read — see `context.theme`.
      extensions: [
        ThemeState(
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          paletteId: palette.id,
        ),
      ],
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
        // Flutter sizes a tooltip to its text and never wraps, so one long
        // sentence becomes a 540px strip laid across whatever it is anchored
        // near — the "Encrypted" chip's ran from the channel header over the
        // sidebar. A ceiling turns those into a block; short ones are
        // unaffected, since this is a max and not a width.
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(K.radiusRow),
          border: Border.all(color: colors.borderElevated),
          boxShadow: AppShadows.popover,
        ),
        textStyle: AppText.meta.copyWith(color: colors.textSecondary),
      ),
      // Flutter 3.41 made buttons show the plain arrow on desktop, following
      // native desktop apps; only the web kept the hand. Rift is a chat app
      // people come to from Discord and the browser, where everything you can
      // click says so, so the hand comes back here for every Material control
      // it uses. `InkWell` has no theme to set this on, so each one passes
      // [WidgetStateMouseCursor.clickable] itself — which, unlike a plain
      // `click`, still falls back to the arrow while a control is disabled.
      iconButtonTheme: const IconButtonThemeData(style: _clickable),
      textButtonTheme: const TextButtonThemeData(style: _clickable),
      filledButtonTheme: const FilledButtonThemeData(style: _clickable),
      checkboxTheme: const CheckboxThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      sliderTheme: const SliderThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
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
          borderRadius: BorderRadius.circular(K.radiusRow),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(K.radiusRow),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(K.radiusRow),
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
        labelSmall: AppText.label.copyWith(color: colors.textTertiary),
      ),
    );
  }

  static ThemeData dark(AppPalette palette) =>
      fromPalette(palette, Brightness.dark);

  static ThemeData light(AppPalette palette) =>
      fromPalette(palette, Brightness.light);
}
