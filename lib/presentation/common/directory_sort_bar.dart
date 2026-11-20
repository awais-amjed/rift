import 'package:material_ui/material_ui.dart';

import '../../data/constants.dart';
import '../../data/enums/directory_sort.dart';
import '../theme/app_text.dart';
import 'selectable_surface.dart';

/// Top or New.
///
/// Two orders and no more. "Top" is the whole point of a like count, and
/// "New" exists because without it a listing made today is behind every one
/// made before it, for as long as it takes to be found — which is the
/// failure mode of ranking by a cumulative count.
class DirectorySortBar extends StatelessWidget {
  final DirectorySort selected;
  final ValueChanged<DirectorySort> onSelected;

  const DirectorySortBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (final sort in DirectorySort.values)
          SelectableSurface(
            selected: sort == selected,
            onTap: () => onSelected(sort),
            borderRadius: BorderRadius.circular(K.radiusPill),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              sort.label,
              style: AppText.secondary.copyWith(
                fontWeight: sort == selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
