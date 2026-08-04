import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_shadows.dart';

/// The card every popover sits in — context menus, the reaction and emoji
/// pickers.
///
/// Elevated surface, hairline ring and a real shadow. A popover that only
/// differed from the panel behind it by a border would read as part of the
/// layout rather than something opened on top of it, and Material's own
/// elevation tint gets the colour wrong on a dark surface, so callers pass
/// `elevation: 0` and let this paint the depth instead.
class PopoverSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  /// The design pins popovers at 15 — between a card (12) and a panel (16),
  /// which is the register something floating sits in.
  static const double radius = 15;

  const PopoverSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: padding,
          decoration: BoxDecoration(
            color: themeState.bgElevated,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: themeState.borderElevated),
            boxShadow: AppShadows.popover,
          ),
          child: child,
        );
      },
    );
  }
}
