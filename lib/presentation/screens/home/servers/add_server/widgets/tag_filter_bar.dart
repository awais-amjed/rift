import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../common/selectable_surface.dart';
import '../../../../../responsive/shell_scope.dart';
import '../../../../../theme/app_text.dart';

/// The browser's tag filter — one chip per tag, at most one selected.
///
/// The tags come from the results on screen rather than from a query of their
/// own, so a chip can only ever offer a filter that has something behind it.
/// Tapping the selected one clears the filter, which is the only way back to
/// everything without reaching for the search box.
class TagFilterBar extends StatelessWidget {
  final List<String> tags;
  final String? selected;
  final ValueChanged<String> onSelected;

  const TagFilterBar({
    super.key,
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final tag in tags)
        SelectableSurface(
          selected: tag == selected,
          onTap: () => onSelected(tag),
          borderRadius: BorderRadius.circular(K.radiusPill),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            tag,
            style: AppText.secondary.copyWith(
              fontWeight: tag == selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
    ];
    // A phone scrolls the chips sideways rather than wrapping them: wrapped,
    // a long tag list pushes every server below the fold.
    if (context.layoutMode.isCompact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 6, children: chips),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}
