import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';

/// A row of tappable pills where exactly one is selected at a time — invite
/// expiry, max uses.
///
/// The pills size to their own labels and wrap, rather than dividing the row
/// evenly: "1 hour" and "Never" are short words, and stretching them to equal
/// thirds turns a compact set of options into a row of wide empty buttons.
class ChipSelector extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const ChipSelector({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(options.length, (i) {
        final selected = i == selectedIndex;
        return SelectableSurface(
          selected: selected,
          onTap: () => onSelected(i),
          borderRadius: BorderRadius.circular(K.radiusPill),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            options[i],
            style: AppText.secondary.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        );
      }),
    );
  }
}
