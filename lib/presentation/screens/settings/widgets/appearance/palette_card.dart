import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'palette_preview.dart';

/// A palette, previewed as the piece of UI it actually changes: a channel row
/// in that palette's own surfaces, selected in its accent, with an unread
/// badge. Three swatches said which colours a palette had; this says what
/// the app looks like in it.
class PaletteCard extends StatelessWidget {
  final AppPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  /// How wide the card is; [width] by default. Narrower than two of those,
  /// the page hands each card half the row instead (see `AppearanceContent`).
  final double width;

  const PaletteCard({
    super.key,
    required this.palette,
    required this.isSelected,
    required this.onTap,
    this.width = PaletteCard.defaultWidth,
  });

  /// A card's width where the row has room for several side by side.
  static const double defaultWidth = 172;

  /// The narrowest a card is stretched or shrunk to share a row; below this
  /// there is one card to a row.
  static const double minWidth = 140;

  /// [AppText.secondary]'s size at [_lineSpacing], twice over — the two lines
  /// every card's description is given whether it fills them or not.
  static const double _lineSpacing = 1.4;
  static const double _lineHeight = 12 * _lineSpacing * 2;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    // The preview is drawn in the palette's own colours for the current
    // brightness, whichever palette is active.
    final preview = themeState.isDarkTheme ? palette.dark : palette.light;

    return SizedBox(
      width: width,
      child: SelectableSurface(
        selected: isSelected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusCard),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PalettePreview(colors: preview),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    palette.name,
                    // The name stays plain in both states — the border and the
                    // check already say which one is chosen, and tinting the
                    // name too would make the selected card read as a link.
                    style: (isSelected ? AppText.strong : AppText.row).copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: K.iconRow,
                    color: themeState.accentBright,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            // Two lines, always. A row of cards is one object, and a
            // one-line description left its card a line shorter than the
            // three beside it — on the selected card, whose border is
            // drawing attention to exactly those edges. Reserved rather
            // than fixed, so the row still holds together when the text is
            // scaled up.
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.textScalerOf(context).scale(_lineHeight),
              ),
              child: Text(
                palette.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(
                  height: _lineSpacing,
                  color: themeState.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
