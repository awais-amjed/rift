import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text.dart';

/// One mock channel row inside a palette card's preview, drawn in that
/// palette's colours rather than the app's.
class PalettePreviewRow extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final PaletteColors colors;

  const PalettePreviewRow({
    super.key,
    required this.label,
    required this.colors,
    this.selected = false,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? colors.channelActiveBg : null,
        borderRadius: BorderRadius.circular(K.radiusRow - 4),
      ),
      child: Row(
        spacing: 5,
        children: [
          Icon(
            Icons.tag,
            size: 11,
            color: selected ? colors.accentBright : colors.textQuaternary,
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.chip.copyWith(
                color: selected
                    ? colors.channelActiveText
                    : colors.textSecondary,
              ),
            ),
          ),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
              child: Text(
                '$count',
                style: AppText.badge.copyWith(color: colors.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
