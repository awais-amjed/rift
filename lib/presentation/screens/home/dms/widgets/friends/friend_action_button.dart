import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';
import 'friend_row_action.dart';

/// The round icon button carrying one [FriendRowAction] at the end of a
/// friend row.
///
/// Filled at rest rather than bare, because these sit in a row of two or three
/// and a bare icon at 16px gives a pointer nothing to aim at. The dangerous
/// ones are tinted red standing still — in a pair of otherwise identical
/// circles, colour that only appears on hover is found by clicking.
class FriendActionButton extends StatelessWidget {
  static const double size = 30;

  final FriendRowAction action;

  const FriendActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final color = action.isDangerous
        ? CustomColors.error
        : themeState.textSecondary;

    return Tooltip(
      message: action.tooltip,
      waitDuration: K.tooltipDelay,
      child: Material(
        color: action.isDangerous
            ? CustomColors.error.withValues(alpha: 0.1)
            : themeState.bgHover,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: action.onTap,
          hoverColor: color.withValues(alpha: 0.14),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(action.icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}
