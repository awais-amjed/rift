import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_palette.dart';
import 'palette_preview_row.dart';

/// A miniature of the sidebar: the panel surface on the canvas, one channel
/// row selected in the accent, one at rest with a count.
class PalettePreview extends StatelessWidget {
  final PaletteColors colors;

  const PalettePreview({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: colors.borderElevated),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: BorderRadius.circular(K.radiusRow - 2),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          spacing: 3,
          children: [
            PalettePreviewRow(label: 'general', selected: true, colors: colors),
            PalettePreviewRow(label: 'design', count: 2, colors: colors),
          ],
        ),
      ),
    );
  }
}
