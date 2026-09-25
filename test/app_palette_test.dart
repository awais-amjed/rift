import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/theme/app_palette.dart';
import 'package:rift/presentation/theme/custom_colors.dart';

/// The redesign's whole structure is a surface *ladder*: the canvas is the
/// darkest thing on screen, panels sit on it, insets sit in them, and elevated
/// chrome floats above. A palette that breaks the ordering doesn't look
/// slightly off — it inverts depth, which is what made the old chat pane read
/// as a hole. These tests pin the ordering so a future palette can't quietly
/// lose it.
void main() {
  /// Perceived brightness, so the assertions match what the eye ranks rather
  /// than raw channel values.
  double lum(Color c) => c.computeLuminance();

  group('every palette', () {
    for (final palette in AppPalette.all) {
      test(
        '${palette.name} dark: canvas → content → panel → inset → elevated',
        () {
          final c = palette.dark;
          expect(lum(c.bgPrimary), lessThan(lum(c.bgContent)));
          expect(lum(c.bgContent), lessThan(lum(c.bgSecondary)));
          expect(lum(c.bgSecondary), lessThan(lum(c.bgTertiary)));
          expect(lum(c.bgTertiary), lessThan(lum(c.bgElevated)));
        },
      );

      test('${palette.name} light: the canvas is darker than the panels', () {
        final c = palette.light;
        // Light mode inverts the middle of the ladder — panels are the
        // brightest thing and the canvas recedes behind them — but the canvas
        // must still be the floor, or the panels stop floating.
        expect(lum(c.bgPrimary), lessThan(lum(c.bgSecondary)));
        expect(lum(c.bgSecondary), lessThanOrEqualTo(lum(c.bgContent)));
        expect(lum(c.bgTertiary), lessThan(lum(c.bgSecondary)));
      });

      test('${palette.name} dark: the text ramp fades', () {
        final c = palette.dark;
        expect(lum(c.textPrimary), greaterThan(lum(c.textSecondary)));
        expect(lum(c.textSecondary), greaterThan(lum(c.textTertiary)));
        expect(lum(c.textTertiary), greaterThan(lum(c.textQuaternary)));
      });

      test('${palette.name} light: the text ramp fades', () {
        final c = palette.light;
        expect(lum(c.textPrimary), lessThan(lum(c.textSecondary)));
        expect(lum(c.textSecondary), lessThan(lum(c.textTertiary)));
        expect(lum(c.textTertiary), lessThan(lum(c.textQuaternary)));
      });

      test('${palette.name}: body text reads against the content panel', () {
        // 4.5:1 is the WCAG AA floor for body text. Only the two ramp stops
        // that carry actual prose are held to it — the lower two are for
        // decoration and metadata.
        for (final mode in [palette.dark, palette.light]) {
          for (final text in [mode.textPrimary, mode.textSecondary]) {
            expect(
              _contrast(text, mode.bgContent),
              greaterThanOrEqualTo(4.5),
              reason: '${palette.name} body text on the content panel',
            );
          }
        }
      });
    }
  });

  group('status ink', () {
    // A status label — "Not encrypted", "Encrypted", "LIVE", a red menu row —
    // is 10–13px text on its own colour washed over a panel. The shared status
    // colours were picked on dark surfaces, and on a light one amber came to
    // 1.55:1; the ink is what a widget draws the *words* in, so it is what has
    // to clear AA.
    const statuses = {
      'success': CustomColors.success,
      'warning': CustomColors.warning,
      'error': CustomColors.error,
    };
    for (final palette in AppPalette.all) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        final state = ThemeState(themeMode: mode, paletteId: palette.id);
        for (final MapEntry(key: name, value: status) in statuses.entries) {
          test('${palette.name} ${mode.name}: $name reads on its wash', () {
            final ink = state.statusInk(status);
            for (final surface in [state.bgContent, state.bgElevated]) {
              final wash = Color.alphaBlend(
                status.withValues(alpha: 0.14),
                surface,
              );
              expect(
                _contrast(ink, wash),
                greaterThanOrEqualTo(4.5),
                reason: '$name ink on its wash over $surface',
              );
            }
          });
        }
      }
    }
  });

  test('palette ids are unique, and an unknown id falls back to indigo', () {
    final ids = AppPalette.all.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(AppPalette.byId('nope').id, 'indigo');
    expect(AppPalette.byId('abyss').id, 'abyss');
  });
}

/// WCAG relative-contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
