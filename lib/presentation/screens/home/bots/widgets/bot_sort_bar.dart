import 'package:flutter/material.dart';

import '../../../../../data/classes/public_bot.dart';
import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';

/// Top or New.
///
/// Two orders and no more. "Top" is the whole point of a like count, and
/// "New" exists because without it a bot listed today is behind every bot
/// listed before it, for as long as it takes to be found — which is the
/// failure mode of ranking by a cumulative count.
class BotSortBar extends StatelessWidget {
  final BotSort selected;
  final ValueChanged<BotSort> onSelected;

  const BotSortBar({
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
        for (final sort in BotSort.values)
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
