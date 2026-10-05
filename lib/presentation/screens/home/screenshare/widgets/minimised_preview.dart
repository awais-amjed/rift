import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Stands in for the picture of a minimised window, which has none until it
/// is back on screen — and says when its share will start: once the user
/// opens it, which Rift leaves to them.
///
/// Three window tiles to a row leave the preview about 40 px tall in the share
/// dialog, less than the icon and both lines need (the overflow stripe on
/// Windows, Oct 5 2026). So it shows what fits, in order of what matters:
/// "Minimised", then when the share starts, then the icon.
class MinimisedPreview extends StatelessWidget {
  const MinimisedPreview({super.key});

  /// "open it" kept together, so a narrow tile does not leave "it" alone.
  static const _starts = 'Starts when you open\u00A0it';
  static const _iconSize = 22.0;
  static const _iconGap = 4.0;
  static const _sidePadding = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final label = AppText.label.copyWith(color: theme.textSecondary);
    final meta = AppText.meta.copyWith(color: theme.textTertiary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 2 * _sidePadding).clamp(
          0.0,
          double.infinity,
        );
        double heightOf(String text, TextStyle style, int lines) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: lines,
          )..layout(maxWidth: width);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final room = constraints.maxHeight;
        final labelHeight = heightOf('Minimised', label, 1);
        final metaHeight = heightOf(_starts, meta, 2);
        final showMeta = labelHeight + metaHeight <= room;
        final showIcon =
            showMeta && labelHeight + metaHeight + _iconSize + _iconGap <= room;

        // Scales down only when even the label does not fit, in a tile far
        // smaller than the dialog makes.
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showIcon) ...[
                      Icon(
                        Icons.minimize_rounded,
                        size: _iconSize,
                        color: theme.textTertiary,
                      ),
                      const SizedBox(height: _iconGap),
                    ],
                    Text(
                      'Minimised',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label,
                    ),
                    if (showMeta)
                      Text(
                        _starts,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: meta,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
