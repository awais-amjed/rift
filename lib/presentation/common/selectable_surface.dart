import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';

/// The wash-and-ring treatment shared by every pick-one control — expiry
/// chips, max-use chips, the text/voice channel type segments.
///
/// Selection is shown by *tinting* the option rather than filling it: a solid
/// accent block reads as a button you still have to press, when the point is
/// that this one is already chosen. A 1px accent border carries the rest —
/// the same width as the resting hairline, so nothing shifts on selection.
/// This is the app's one selection language; rows and cards use the same
/// tint and border.
///
/// Icon and label colours are set here via [IconTheme] and [DefaultTextStyle],
/// so callers supply only size and weight and can't drift on the palette.
class SelectableSurface extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final Widget child;

  const SelectableSurface({
    super.key,
    required this.selected,
    required this.onTap,
    required this.borderRadius,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: selected ? themeState.channelActiveBg : themeState.bgHover,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            hoverColor: selected ? Colors.transparent : themeState.bgActive,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: selected
                      ? themeState.channelActiveBorder
                      : themeState.borderElevated,
                ),
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: selected
                      ? themeState.accentBright
                      : themeState.textTertiary,
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: selected
                        ? themeState.channelActiveText
                        : themeState.textSecondary,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
